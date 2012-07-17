require 'thor'
require 'net/ssh'

trap("INT"){ exit -1 }

class Scalarium
  class CLI < Thor
    include Thor::Actions

    class CloudNotFound         < Exception; end
    class RolOrInstanceNotFound < Exception; end
    class AppNotFound           < Exception; end

    desc 'sshconfig CLOUD', "Create ssh hosts for your infraestructure in ~/.ssh/config"
    method_option :certificate, :aliases => "-i", :desc => "specify alternate certificate for login"
    def sshconfig(cloud_names)
      with_scalarium(cloud_names) do |scalarium,clouds|


        config_file = File.expand_path("~/.ssh/config")
        header      = "# Added by scalarium"
        tail        = "# Do not modify"

        if File.exists?(config_file)
          config = File.read(config_file)
          config.gsub!(/#{header}.*#{tail}/mi,'')
        else
          config = ""
        end

        config  << header << "\n"

        clouds.threaded_each do |cloud|
          cloud.instances.each do |instance|
            Thread.exclusive do
              say_status(cloud.name, instance.nickname)
              config << format_ssh_config_host(instance)
            end
          end
        end

        config << "\n" << tail << "\n"

        File.open(config_file,'w'){|f|
          f.rewind
          f.write config
        }
        say("Configuration file updated")
      end
    end

    desc 'execute CLOUDNAME ROL_OR_INSTANCE COMMAND', "Execute a command in a cloud.\nUse 'all' as instance to execute in all instances."
    def execute(cloud_name, rol_or_instance, command)
      with_scalarium(cloud_name) do |scalarium, clouds|

        clouds.each do |cloud|
          instances = cloud.find_instances(rol_or_instance) or raise RolOrInstanceNotFound.new(rol_or_instance)

          instances.threaded_each do |instance|
            run_remote_command(instance, command)
          end
        end
      end
    end

    desc 'run_remote CLOUDNAME ROL_OR_INSTANCE COMMAND', "Run a remote command and shows its output through tmux.\n Use all to run the command in all the instances."
    def run_remote(cloud_name, rol_or_instance, command)
      with_scalarium(cloud_name) do |scalarium, clouds|

        instances = []
        clouds.each do |cloud|
          instances = cloud.find_instances(rol_or_instance) or raise RolOrInstanceNotFound.new(rol_or_instance)
        end
        instances.flatten!

        total_instances = instances.size
        command = "#{command} ; read"
        session_name = "scalarium_gem#{Time.now.to_i}#{Time.now.usec}"
        puts "Launching in #{instances.map{|i| i.nickname}}"
        system(%{tmux new-session -d -n #{session_name} -s #{session_name} "ssh -t #{instances.shift.nickname} \\"#{command}\\""})
        while(instance = instances.shift) do
          system(%{tmux split-window -h -p #{100/total_instances*(instances.size+1)} -t #{session_name} "ssh -t #{instance.nickname} \\"#{command}\\""})
        end
        system("tmux select-window -t #{session_name} ")
        system("tmux select-layout -t #{session_name} tiled")
        exec("tmux -2 attach-session -t #{session_name} ")

      end
    end

    desc 'update_cookbooks CLOUDNAME', "Make instances to pull changes from recipies repository"
    method_option :cloud, :aliases => "-c", :desc => "only for clouds matchin this regexp"
    def update_cookbooks(cloud_name)
      with_scalarium(cloud_name) do |scalarium,clouds|

        clouds.each do |cloud|
          puts "Updating cookbooks for #{cloud.name}"

          deploy_info = cloud.update_cookbooks!

          puts "Waiting the deploy finish"
          puts "Check https://manage.scalarium.com/clouds/#{cloud.id}/deployments/#{deploy_info["id"]} if you want"
          while deploy_info["status"] == 'running'
            sleep 1
            deploy_info = cloud.check_deploy(deploy_info["id"])
          end
          puts "Deploy was #{deploy_info["status"]}"
          exit (deploy_info["status"] == 'successful' ? 0 : -1)
        end
      end
    end

    desc 'configure ROL_OR_INSTANCE', 'Trigger configure event'
    def configure(rol_or_instance)
      # /clouds/07/instances/e5/chef?chef_action=setup
      # /clouds/07/instances/e5/chef?chef_action=configure
    end

    desc 'run_recipe CLOUDNAME ROL_OR_INSTANCE RECIPE', 'Execute recipes in given'
    def run_recipe(cloudname, rol_or_instances, recipes_names)
      with_scalarium(cloudname) do |scalarium, clouds|

        clouds.each do |cloud|

          instances = cloud.find_instances(rol_or_instances) or raise RolOrInstanceNotFound.new(rol_or_instances)
          instance_ids = instances.map{|i| i.id}

          deploy_info = cloud.run_recipe!(recipes_names, instance_ids)

          puts "Waiting the recipe to finish"
          puts "Check https://manage.scalarium.com/clouds/#{cloud.id}/deployments/#{deploy_info["id"]} if you want"
          while deploy_info["status"] == 'running'
            sleep 1
            deploy_info = cloud.check_deploy(deploy_info["id"])
          end
          puts "Deploy was #{deploy_info["status"]}"
          exit (deploy_info["status"] == 'successful' ? 0 : -1)
        end
      end
    end

    desc 'deploy APP', "Deploy application named APP"
    def deploy(name)
      with_scalarium do |scalarium|
        app = scalarium.find_app(name) or raise AppNotFound.new(name)

        deploy_info = app.deploy!

        puts "Waiting the deploy finish"
        puts "Check https://manage.scalarium.com/applications/#{app.id}/deployments/#{deploy_info["id"]} if you want"
        while deploy_info["status"] == 'running'
          sleep 1
          deploy_info = app.deploy_info(deploy_info["id"])
        end
        puts "Deploy was #{deploy_info["status"]}"
        exit (deploy_info["status"] == 'successful' ? 0 : -1)
      end
    end

    desc 'apps [APPNAME]', "List the apps\n\nIf APPNAME is defined, show extended information about the app"
    def apps(app_name = nil)
      with_scalarium do |scalarium|
        if app_name
          app = scalarium.find_app(app_name) or raise AppNotFound.new(app_name)
          cool_inspect(app)
        else
          scalarium.apps.each { |app| say app.name, Color::BLUE }
        end
      end
    end


    desc 'clouds [CLOUDNAME]', "Show Clouds, Roles and Instance names"
    method_option :verbose, :aliases => "-v", :desc => "Show all the availabe", :type => :boolean
    def clouds(cloud_name = "all")
      with_scalarium(cloud_name) do |scalarium,clouds|

        clouds.threaded_each{ |c|
          if cloud_name != 'all'
            DQ[ lambda{ c.instances }, lambda{c.roles} ]
            Thread.exclusive do
              print_cloud(c, options[:verbose])
            end
          else
            puts c.name
          end
        }

      end
    end

    protected

    def run_remote_command(instance, command)
      host = instance.nickname
      puts "Oppening connection to host #{host}" if $DEBUG
      Net::SSH.start(host, ENV["USER"]) do |ssh|
        puts "Executing #{command}" if $DEBUG
        ssh.exec!(command) do |channel, stream, data|
          Thread.exclusive do
            case stream
            when :stdout
              $stdout.puts("#{Color::GREEN}%10s: #{Color::CLEAR}%s" %[ host, data])
            when :stderr
              $stderr.puts("#{Color::GREEN}%10s: #{Color::CLEAR}%s" %[ host, data])
            end
          end
        end
      end
    rescue Net::SSH::AuthenticationFailed
      Thread.exclusive do
        $stderr.puts "#{Color::RED}Could not execute a command in #{host} because auth problems"
        $stderr.puts "Check that you can access #{host} through 'ssh #{host}' as your username (ENV['USER'])#{Color::CLEAR}"
      end
    rescue Net::SSH::HostKeyMismatch
      Thread.exclusive do
        $stderr.puts "#{Color::RED}Could not execute a command in #{host} because HostKeyMismatch"
        $stderr.puts "Remove the entry in ~/.ssh/know_hosts for #{instance.ip} #{Color::CLEAR}"
      end
    rescue SocketError
      Thread.exclusive do
        $stderr.puts "#{Color::RED}Cold not connect to #{host} due connection problems#{Color::CLEAR}"
      end
    end

    def format_ssh_config_host(instance)
      return "" if instance.ip.to_s.strip.empty?
      host = "\nHost #{instance.nickname}\n" << "    Hostname #{instance.ip}\n"
      host << "    IdentityFile #{options[:certificate]}" if options[:certificate]
      host
    end

    def with_scalarium(cloud_name = nil)
      scalarium = ::Scalarium.new( get_token )
      cloud = scalarium.find_clouds(cloud_name) or raise CloudNotFound.new(cloud_name) if cloud_name

      yield scalarium, cloud

    rescue ::RestClient::Unauthorized
      say("The token is not valid", Color::RED)
      File.unlink token_path
      retry
    rescue ::OpenSSL::SSL::SSLError, ::RestClient::ServerBrokeConnection
      say("There were problems with ssl. Pleas retry")
      exit -2
    rescue ::Errno::ETIMEDOUT
      say("There were problems with connection (timeout)")
      exit -3
    rescue CloudNotFound => e
      say("Can't find a cloud named #{e.message}")
      exit -4
    rescue RolOrInstanceNotFound => e
      say("Can't find a rol or instances with name #{e.message}")
      exit -4
    rescue AppNotFound => e
      say("Can't find a app with name #{e.message}")
      exit -4
    end

    def get_token
      if File.exists?(token_path)
        token = File.read(token_path).strip
      else
        token = ask("I need your token:").strip
        File.open(token_path, 'w', 0600){|f| f.write token }
      end
      token
    end

    def token_path
      File.expand_path("~/.scalarium_token")
    end

    def print_cloud(cloud, verbose=false)
      say "#{cloud.name} (#{cloud.id[0..6]})", Color::GREEN
      return cool_inspect(cloud, 2) if verbose
      cloud.roles.each do |rol|
        say "  #{rol.name}", Color::BLUE
        if verbose
          cool_inspect(role, 2)
        else
          rol.instances.each do |instance|
            puts "    #{instance.nickname} (#{instance.ip})"
          end
        end
      end
    end

    def cool_inspect(what, indent = 0)
      case what
      when OpenStruct
        cool_inspect( what.instance_variable_get("@table"), indent)
      when Hash
        what.each do |key,value|
          case value
          when String, Integer, false, true, nil
            if value.is_a?(String)
              value = value.size > 50 ? value[0..50].inspect+"..." : value.inspect
            else
              value = value.inspect
            end
            say( " " * indent+ key.to_s + ": " + Color::BLACK + value, Color::YELLOW)
          else
            if (what === Array || what === Hash) && what.size == 0
              say( " " * indent + key.to_s + ": " + Color::MAGENTA + what.inspect, Color::YELLOW)
            else
              say( " " * indent+ key.to_s + ": ", Color::YELLOW)
              cool_inspect(value, indent + 2)
            end
          end
        end
      when Array
        say( " " * indent + '[', Color::MAGENTA)
        what.each_with_index do |value, index|
          print " " * indent + index.to_s + "."
          cool_inspect(value, indent + 2)
        end
        say( " " * indent + ']', Color::MAGENTA)
      when String
        if what.size > 30
          say((" " * indent + wath[0..30].inspect + "..."), Color::Black)
        else
          say((" " * indent + what.inspect ), Color::BLACK)
        end
      else
        say((" " * indent + what.inspect ), Color::BLACK)
      end
    end

  end
end
