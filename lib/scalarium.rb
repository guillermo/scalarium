require "scalarium/version"
require 'rest-client'
require 'json'
require 'dispatch_queue'
require 'ostruct'

class Scalarium
  class Instance < OpenStruct ; end
  class Rol     < OpenStruct ; end
  class Cloud    < OpenStruct ; end

  attr_reader :clouds
  def initialize(token, cloud = nil)
    @token = token
    @clouds = []

    @clouds = get('clouds').map{|c| Cloud.new(c) }

    return if cloud == false

    if cloud != nil
      filtered_clouds = @clouds.select do |c|
        (c.name =~ /#{cloud}/i) || c.name.downcase.include?(cloud.downcase)
      end
      @clouds = filtered_clouds || []
    end
    DQ[*(@clouds.map {  |cloud| lambda { process_cloud(cloud) } })]
  end

  private

  def get(resource)
    $stderr.puts "Getting #{resource}" if $DEBUG
    url = "https://manage.scalarium.com/api/#{resource}"
    headers = {
      'X-Scalarium-Token' => @token,
      'Accept' => 'application/vnd.scalarium-v1+json'
    }
    response = RestClient.get(url, headers)
    JSON.parse(response)
  end

  def get_roles_proc(cloud_id)
    lambda do
      get("clouds/#{cloud_id}/roles").map { |hash|
        Rol.new(hash)
      }
    end
  end

  def get_instances_proc(cloud_id)
    lambda do
      get("clouds/#{cloud_id}/instances").map { |hash|
        Instance.new(hash)
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

