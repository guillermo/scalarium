# @nodoc
class Scalarium
  module Api
    class TokenNotFound < StandardError; end

    def get(resource)
      raise TokenNotFound unless @token
      $stderr.puts "Getting #{resource}" if $DEBUG
      url = "https://manage.scalarium.com/api/#{resource}"
      headers = {
        'X-Scalarium-Token' => @token,
        'Accept' => 'application/vnd.scalarium-v1+json'
      }
      response = RestClient.get(url, headers)
      JSON.parse(response)
    end

    def post(resource, data)
      raise TokenNotFound unless @token
      $stderr.puts "Posting #{data.inspect} to #{resource}" if $DEBUG
      url = "https://manage.scalarium.com/api/#{resource}"
      headers = {
        'X-Scalarium-Token' => @token,
        'Accept' => 'application/vnd.scalarium-v1+json'
      }
      response = RestClient.post(url, JSON.dump(data), headers)
      JSON.parse(response)
    end


  end
end
