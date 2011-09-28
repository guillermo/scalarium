
class Scalarium
  class Cloud
    class Rol < Resource

      def initialize(token, cloud, hash)
        super(token,hash)
        @cloud = cloud
      end

      def instances
        @cloud.instances.select{|i| i.role_ids.include?(self.id)}
      end

    end
  end
end
