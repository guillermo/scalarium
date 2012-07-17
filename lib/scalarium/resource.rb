class Scalarium
  class Resource < OpenStruct
    include Scalarium::Api
    def initialize(token, attributes = {})
      @token = token
      super(attributes)
    end

    def id
      @table[:id]
    end
  end
end
