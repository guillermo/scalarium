class Scalarium
  class Resource < OpenStruct
    include Scalarium::Api
    def initialize(token, attributes = {})
      @token = token
      super(attributes)
    end
  end
end
