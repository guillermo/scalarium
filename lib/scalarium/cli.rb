require 'thor'
require 'net/ssh'

trap("INT"){ exit -1 }

class Scalarium
  class CLI < Thor
    include Thor::Actions
    desc 'update_sshconfig', "Create ssh hosts for your infraestructure in ~/.ssh/config"
    method_option :cloud, :aliases => "-c", :desc => "only for clouds matchin this regexp"
    method_option :certificate, :aliases => "-i", :desc => "specify alternate certificate for login"
    def update_sshconfig
      capture_exceptions do
        scalarium = ::Scalarium.new( get_token, options[:cloud] )

        config_file = File.expand_path("~/.ssh/config")
        header = "# Added by scalarium"
        tail = "# Do not modify"
        if File.exists?(config_file)
          config = File.read(config_file)
          config.gsub!(/#{header}.*#{tail}/mi,'')
        else
          config = ""
        end

        config  << header << "\n"
        scalarium.clouds.each do |cloud|
          say "Adding hosts from #{cloud.name}"
          cloud.instances.each do |instance|
            config << format_ssh_config_host(instance)
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

    desc 'execute COMMAND', "Execute a command in a cloud"
    method_option :cloud, :aliases => "-c", :desc => "only for clouds matchin this regexp"
    method_option :instance, :aliases => "-i", :type => :array, :desc => "List of instances: -i instace1 instace2"
    def execute(command)

      capture_exceptions do
        scalarium = ::Scalarium.new(get_token, options[:cloud])
        instances = nil

        if scalarium.clouds.size > 1
          $stderr.puts "This operation should be done in only one cloud"
          exit -1
        elsif scalarium.clouds.size < 1
          $stderr.puts "You should select at least one cloud"
          exit -2
        end
        cloud = scalarium.clouds.first
        hosts = get_instances(cloud, options[:instances]).map{|i| i.nickname}

        hosts.threaded_each do |host|
          run_remote_command(host, command)
        end
      end
    end

    desc 'update_cookbooks', "Make instances to pull changes from recipies repository"
    method_option :cloud, :aliases => "-c", :desc => "only for clouds matchin this regexp"
    def update_cookbooks
      capture_exceptions do
        scalarium = ::Scalarium.new(get_token, options[:cloud])

        scalarium.clouds.each do |cloud|
          puts "Updating cookbooks for #{cloud.name}"

          deploy_info = cloud.update_cookbooks!

          puts "Waiting the deploy finish"
          puts "Check https://manage.scalarium.com/clouds/#{cloud.id}/deployments/#{deploy_info["id"]} if you want"
          while deploy_info["successful"] == nil
            sleep 1
            deploy_info = cloud.check_deploy(deploy_info["id"])
          end
          puts "Deploy was #{deploy_info["successful"]}"
          exit (deploy_info["successful"] ? 0 : -1)
        end
      end
    end

    desc 'run_recipe RECIPE', 'Execute recipes in given'
    method_option :cloud, :aliases => "-c", :desc => "only for clouds matchin this regexp"
    method_option :instance, :aliases => "-i", :type => :array, :desc => "List of instances: -i instace1 instace2"
    def run_recipe(recipes_names)
      capture_exceptions do
        scalarium = ::Scalarium.new(get_token, options[:cloud])
        instances = nil

        if scalarium.clouds.size > 1
          $stderr.puts "This operation should be done in only one cloud"
          exit -1
        elsif scalarium.clouds.size < 1
          $stderr.puts "You should select at least one cloud"
          exit -2
        end
        cloud = scalarium.clouds.first
        instances = options[:instance] ? get_instances_ids(cloud, options[:instance]) : nil

        deploy_info = cloud.run_recipe!(recipes_names, instances)

        puts "Waiting the recipe to finish"
        puts "Check https://manage.scalarium.com/clouds/#{cloud.id}/deployments/#{deploy_info["id"]} if you want"
        while deploy_info["successful"] == nil
          sleep 1
          deploy_info = cloud.check_deploy(deploy_info["id"])
        end
        puts "Deploy was #{deploy_info["successful"]}"
        exit (deploy_info["successful"] ? 0 : -1)
      end
    end

    desc 'deploy APP', "Deploy application named APP"
    def deploy(name)
      capture_exceptions do
        scalarium = ::Scalarium.new(get_token, false)

        all_apps = scalarium.apps
        posible_apps = all_apps.select{|app|
          [app.name, app.slug_name].any?{|a| a =~ Regexp.new(name, ::Regexp::IGNORECASE)}
        }
        if posible_apps.size > 1
          $stderr.puts "Found more than one application matching #{name}"
          posible_apps.each do |app|
            puts " #{app.name} (#{app.slug_name}) "
          end
        elsif posible_apps.size == 0
          $stderr.puts "App with name #{name} not found"
          available_apps = all_apps.map {|app|
            "#{app.name} (#{app.slug_name})"
          }
          $stderr.puts "Available apps: #{available_apps.join(" ")}"
        else
          app = posible_apps.first

          deploy_info = app.deploy!

          puts "Waiting the deploy finish"
          puts "Check https://manage.scalarium.com/applications/#{app.id}/deployments/#{deploy_info["id"]} if you want"
          while deploy_info["successful"] == nil
            sleep 1
            deploy_info = app.deploy_info(deploy_info["id"])
          end
          puts "Deploy was #{deploy_info["successful"]}"
          exit (deploy_info["successful"] ? 0 : -1)
        end
      end

    end

    desc 'apps', "List the apps"
    method_option :cloud, :aliases => "-c", :desc => "only for clouds matchin this regexp"
    def apps
      capture_exceptions do
        scalarium = ::Scalarium.new( get_token, false )

        scalarium.apps.each do |app|
          say app.name, Color::BLUE
          cool_inspect(app, 2)
        end
      end
    end



    desc 'inspect', "Show Clouds, Roles and Instance names"
    method_option :cloud, :aliases => "-c", :desc => "only for clouds matchin this regexp"
    method_option :verbose, :aliases => "-v", :desc => "Show all the availabe", :type => :boolean
    def inspect
      capture_exceptions do
        load_all = options[:cloud]
        load_all = false if options[:verbose]
        scalarium = ::Scalarium.new( get_token, load_all )

        scalarium.clouds.each do |cloud|
          print_cloud(cloud, options[:verbose])
        end
      end
    end

    desc 'clouds', "List the clouds"
    def clouds
      capture_exceptions do
        scalarium = ::Scalarium.new( get_token, false )
        scalarium.clouds.each do |cloud|
          puts cloud.name
        end
      end
    end


    protected

    def run_remote_command(host, command)
      puts "Oppening connection to host #{host}" if $DEBUG
      Net::SSH.start(host, ENV["USER"]) do |ssh|
        puts "Executing #{command}" if $DEBUG
        ssh.exec!(command) do |channel, stream, data|
          Thread.exclusive do
            case stream
            when :stdout
              $stdout.puts ("#{Color::GREEN}%10s: #{Color::CLEAR}%s" %[ host, data])
            when :stderr
              $stderr.puts ("#{Color::GREEN}%10s: #{Color::CLEAR}%s" %[ host, data])
            end
          end
        end
      end
    rescue Net::SSH::AuthenticationFailed
      Thread.exclusive do
        $stderr.puts "#{Color::RED}Could not execute a command in #{host} because auth problems"
        $stderr.puts "Check that you can access #{host} through 'ssh #{host}' as your username (ENV['USER'])#{Color::CLEAR}"
      end
    rescue SocketError
      Thread.exclusive do
        $stderr.puts "#{Color::RED}Cold not connect to #{host} due connection problems#{Color::CLEAR}"
      end
    end

    def get_instances_ids(cloud, instances)
      get_instances(cloud, instances).map{|i| i.id }
    end

    def get_instances(cloud, instances)
      return cloud.instances if instances.nil? || instances.empty?
      posible_instances = cloud.instances.select{|instance|
        instances.include?(instance.nickname.downcase)
      }
      if posible_instances.size != instances.size
        if posible_instances.size == 0
          $stderr.puts "Not to be able to found any instance with name/names #{instances}"
        else
          $stderr.puts "Only be able to found #{posible_instances.map{|i| i.nickname}.join(" ")} instances"
        end
        exit -3
      end
      posible_instances
    end

    def format_ssh_config_host(instance)
      return "" if instance.ip.to_s.strip.empty?
      host = "\nHost #{instance.nickname}\n" << "    Hostname #{instance.ip}\n"
      host << "    IdentityFile #{options[:certificate]}" if options[:certificate]
      host
    end

    def capture_exceptions
      yield
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
    end

    def get_token
      if File.exists?(token_path)
        token = File.read(token_path).strip
      else
        token = ask("I need your token:").strip
        File.open(token_path, 'w'){|f| f.write token }
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
            say( " " * indent+ key.to_s + ": " + Color::BLACK + value.inspect, Color::YELLOW)
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
          say( " " * indent + index.to_s + ".")
          cool_inspect(value, indent + 2)
        end
        say( " " * indent + ']', Color::MAGENTA)
      else
        say((" " * indent + what.inspect ), Color::BLACK)
      end
    end

  end
end
