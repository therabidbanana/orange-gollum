libdir = File.dirname(__FILE__)
$LOAD_PATH.unshift(libdir) unless $LOAD_PATH.include?(libdir)

require 'gollum'
require 'orange-core'
require 'orange-gollum/plugin'