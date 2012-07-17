if RUBY_VERSION < '1.9'
  # monkey patching open struct to allow overwriting id method
  OpenStruct.__send__(:define_method, :id) { @table[:id] }
end

class Scalarium
  class Resource < OpenStruct
    include Scalarium::Api
    def initialize(token, attributes = {})
      @token = token
      super(attributes)
    end
  end
end
