require 'orange-core'
require 'orange-gollum/resources/gollum_resource'

module Orange::Plugins
  class Gollum < Base
    assets_dir      File.join(File.dirname(__FILE__), 'assets')
    views_dir       File.join(File.dirname(__FILE__), 'views')
    templates_dir   File.join(File.dirname(__FILE__), 'templates')
    
    resource    Orange::GollumResource.new
  end
end

Orange.plugin(Orange::Plugins::Gollum.new)

