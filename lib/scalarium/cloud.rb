
class Scalarium
  class Cloud < Resource
    def update_cookbooks!
      post("clouds/#{object_id}/deploy", :command => 'update_custom_cookbooks' )
    end

    def check_deploy(deploy_id)
      get("clouds/#{object_id}/deployments/#{deploy_id}")
    end

    def run_recipe!(recipe, instances = nil)
      opt = {:command => "execute_recipes", :recipes => recipe}
      opt[:instances] = instances if instances

      post("clouds/#{object_id}/deploy", opt)
    end

    def instances
      return @instances if @instances
      @instances = get("clouds/#{object_id}/instances").map{|hash|
        Instance.new(@token, self, hash)
      }
    end

    def find_instance(name_or_id)
      instances.find{|i| [i.name.downcase, i.nickname.downcase, i.id].include?(name_or_id.downcase)}
    end

		def find_instances(rol_or_instance)
			return instances  if rol_or_instance == "all"
			rol = find_rol(rol_or_instance)
			return rol.instances if rol
			instance = find_instance(rol_or_instance)
			return [instance] if instance
			nil
		end

    def roles
      return @roles if @roles
      @roles = get("clouds/#{object_id}/roles").map{|hash|
        Rol.new(@token, self, hash)
      }
    end

    def find_rol(name_or_id)
      roles.find{|r| [r.name.downcase, r.shortname.downcase, r.id].include?(name_or_id.downcase)}
    end
  end
end
