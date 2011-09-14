
class Scalarium
  class Cloud < Resource
    def update_cookbooks!
      post("clouds/#{id}/deploy", :command => 'update_custom_cookbooks' )
    end

    def check_deploy(deploy_id)
      get("clouds/#{id}/deployments/#{deploy_id}")
    end

    def run_recipe!(recipe, instances = nil)
      opt = {:command => "execute_recipes", :recipes => recipe}
      opt[:instances] = instances if instances

      post("clouds/#{id}/deploy", opt)
    end
  end
end
