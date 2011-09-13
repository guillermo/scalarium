require 'thor'

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

    desc 'update_cookbooks', "Make instances to pull changes from recipies repository"
    method_option :cloud, :aliases => "-c", :desc => "only for clouds matchin this regexp"
    def update_cookbooks
      capture_exceptions do
        scalarium = ::Scalarium.new(get_token, options[:cloud])

        scalarium.clouds.each do |cloud|
          puts "Updating cookbooks for #{cloud.name}"
          next unless (ask "Continue? (say yes)").strip == "yes"

          deploy_info = cloud.update_cookbooks!

          puts "Waiting the deploy finish"
          puts "Check https://manage.scalarium.com/clouds/#{cloud.id}/deployments/#{deploy_info["id"]} if you want"
          while deploy_info["successful"] == nil
            sleep 1
            deploy_info = cloud.check_deploy(deploy_info["id"])
          end
          puts "Deploy was #{deploy_info["successful"]}"
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
