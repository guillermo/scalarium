require 'rubygems'
require 'test/unit'

$:.unshift(File.dirname(File.dirname(__FILE__)) + '/lib')

require 'scalarium'

class TestCloud < Test::Unit::TestCase

  # nail a bug on Ruby < 1.9
  def testIdOnCloud
    c = Scalarium::Cloud.new('foo', {"id" => "cloud_id"})
    assert_equal("cloud_id", c.id)
  end

end
