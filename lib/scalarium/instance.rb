
class Scalarium
  class Cloud
    class Instance < Resource

      def initialize( token, cloud, hash )
        super(token,hash)
        @cloud = cloud
      end

    end
  end
end
