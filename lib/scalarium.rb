require 'rest-client'
require 'json'
require 'dispatch_queue'
require 'ostruct'

require "scalarium/version"
require "scalarium/api"
require "scalarium/resource"
require "scalarium/cloud"

class Scalarium
  include Scalarium::Api

  class Instance < Resource ; end
  class Rol      < Resource ; end
  class App      < Resource ; end

  attr_reader :clouds

  #
  # cloud could be:
  #   nil    => Fetch infor from all clouds
  #   string => Regular expresion that will match cloud names
  #   false  => Don't fetch neighter roles neigher instances
  #
  def initialize(token, cloud = nil)
    @token = token
    @clouds = []

    @clouds = get('clouds').map{|c| Cloud.new(@token,c) }

    return if cloud == false

    if cloud != nil
      filtered_clouds = @clouds.select do |c|
        (c.name =~ /#{cloud}/i) || c.name.downcase.include?(cloud.downcase)
      end
      @clouds = filtered_clouds || []
    end
    DQ[*(@clouds.map {  |cloud| lambda { process_cloud(cloud) } })]
  end

  def apps
    apps = get('applications').map{ |app|  App.new(@token,app) }
    require 'ruby-debug'
    debugger
    debugger

    puts apps.inspect
    apps
  end

  protected


  def get_roles_proc(cloud_id)
    lambda do
      get("clouds/#{cloud_id}/roles").map { |hash|
        Rol.new(@token,hash)
      }
    end
  end

  def get_instances_proc(cloud_id)
    lambda do
      get("clouds/#{cloud_id}/instances").map { |hash|
        Instance.new(@token,hash)
      }
    end
  end

  def process_cloud(cloud)
    roles, instances = DQ[ get_roles_proc(cloud.id) , get_instances_proc(cloud.id)  ]
    cloud.roles = roles
    cloud.instances = instances
    roles.each do |rol|
      rol.instances = instances.select{|instance| instance.role_ids.include?(rol.id)}
    end
  end
end

