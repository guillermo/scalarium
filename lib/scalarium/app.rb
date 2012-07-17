class Scalarium
  class App < Resource

    def deploy!
      post("applications/#{object_id}/deploy", :command => 'deploy')
    end

    def deploy_info(deploy_id)
      get("applications/#{object_id}/deployments/#{deploy_id}")
    end

    def deploys
      get("applications/#{object_id}/deployments")
    end

  end
end
