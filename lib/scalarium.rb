require 'rest-client'
require 'json'
require 'dispatch_queue'
require 'ostruct'

require "scalarium/version"
require "scalarium/api"
require "scalarium/resource"
require "scalarium/cloud"
require "scalarium/instance"
require "scalarium/rol"
require "scalarium/app"

class Scalarium
  include Scalarium::Api

  class CloudNotFound < Exception; end

  def initialize(token)
    @token = token
  end

  def clouds
    return @clouds if @clouds
    @clouds = get('clouds').map{|c| Cloud.new(@token,c) }
  end

  def find_cloud(name)
    clouds.find{|c| c.name.downcase == name.downcase}
  end

  def find_clouds(names)
    return clouds if names == "all"
    clouds = []
    names.split(",").each do |cloud_name|
      clouds << find_cloud(cloud_name) or raise CloudNotFound.new(cloud_names)
    end
    clouds
  end

  def apps
    return @apps if @apps
    @apps = get('applications').map{ |app|  App.new(@token,app) }
  end

  def find_app(name)
    apps.find{|c| c.name.downcase == name.downcase}
  end

  protected

  def process_cloud(cloud)
    roles, instances = DQ[ get_roles_proc(cloud.id) , get_instances_proc(cloud.id)  ]
    cloud.roles = roles
    cloud.instances = instances
    roles.each do |rol|
      rol.instances = instances.select{|instance| instance.role_ids.include?(rol.id)}
    end
  end
end

