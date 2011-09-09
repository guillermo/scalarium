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

    desc 'inspect', "Show Clouds, Roles and Instance names"
    method_option :cloud, :aliases => "-c", :desc => "only for clouds matchin this regexp"
    def inspect
      capture_exceptions do
        scalarium = ::Scalarium.new( get_token, options[:cloud] )

        scalarium.clouds.each do |cloud|
          print_cloud(cloud)
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
    rescue ::OpenSSL::SSL::SSLError
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

    def print_cloud(cloud)
      say "#{cloud.name} (#{cloud.id[0..6]})", Color::GREEN
      cloud.roles.each do |rol|
        say "  #{rol.name}", Color::BLUE
        rol.instances.each do |instance|
          puts "    #{instance.nickname} (#{instance.ip})"
        end
      end
    end

  end
end
