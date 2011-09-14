class Scalarium
  class App < Resource

    def deploy!
      post("applications/#{id}/deploy", :command => 'deploy')
    end

    def deploy_info(deploy_id)
      get("applications/#{id}/deployments/#{deploy_id}")
    end

    def deploys
      get("applications/#{id}/deployments")
    end

  end
end
