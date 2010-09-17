require 'rubygems'
require 'bundler'
Bundler.setup
require 'orange-sparkles'
require '../lib/orange-gollum'

app = Orange::SparklesApp.app
app.orange.options["main_user"] = "therabidbanana@gmail.com"
app.orange.options["gollum_path"] = File.join(File.dirname(__FILE__), 'orange.wiki.git')
app.orange.options["sparkles.default_style"] = true
run app