
class Scalarium
  class Cloud < Resource
    def update_cookbooks!
      post("clouds/#{id}/deploy", :command => 'update_custom_cookbooks' )
    end

    def check_deploy(deploy_id)
      get("clouds/#{id}/deployments/#{deploy_id}")
    end
  end
end
