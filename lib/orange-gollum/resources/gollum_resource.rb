require 'orange-core'
require 'gollum'
class Orange::GollumResource < Orange::Resource
  call_me :gollum
  
  def exposed(packet); [:index]; end
  
  def stack_init
    options[:path] = orange.options["gollum_path"]
  end
  
  def commit_message(packet)
    { :message => packet.request.params["message"],
      :name => packet['user.id'] || 'anonymous',
      :email => packet['user.id'] || 'anon@orangerb.com'}
  end
  
  def wiki_url(packet)
    orange[:sitemap].url_for(packet, :resource => "gollum")
  end
  
  def gollum(packet)
    ::Gollum::Wiki.new(options[:path], {:base_path => wiki_url(packet)})
  end
  
  def authorize!(packet)
    unless packet["user.id"]
      packet.flash["user.after_login"] = packet["route.path"]
      packet.flash["login.message"] = "Please provide a valid OpenID to edit the wiki."
      packet.reroute('/login')
      return false
    end
    return true
  end
  
  def view(packet = false, *args)
    %w(editbar gollum screen syntax).each{|css| packet.add_css("#{css}.css", :module => "_gollum_")}
    %w(previewable_comment_form tabs text_selection.min).each{|js| packet.add_js("jquery.#{js}.js", :module => "_gollum_")}
    packet.add_js("gollum.js", :module => "_gollum_")
    packet.add_js("MathJax/MathJax.js", :module => "_gollum_")
    opts = args.extract_options!
    path = opts[:path] || packet['route.resource_path'] || "/Home"
    path = "/Home" if path.blank?
    path_parts = path.split('/')
    path_parts.shift
    if %w(edit history compare create preview).include?(path_parts.first)
      action = path_parts.shift
    else
      action = "show"
    end
    opts[:path] = path_parts.join('/')
    self.__send__(action.to_sym, packet, opts)
  end
  
  def create(packet, opts = {})
    authorize!(packet)
    path = opts[:path] || packet['route.resource_path'] || "Home"
    if packet.request.post?
      name = packet.request.params["page"]
      wiki = gollum(packet)
      format = "markdown".intern
      begin
        wiki.write_page(name, format, packet.request.params["content"], commit_message(packet))
        packet.reroute(wiki_url(packet) + name)
      rescue Exception => e
        do_view(packet, :error, {:message => "Errored: #{e.inspect}"})
      end
    else
      opts[:name] ||= path
      opts[:title] ||= path.gsub('-', ' ')
      do_view(packet, :create, opts)
    end
    
  end
  
  def edit(packet, opts = {})
    authorize!(packet)
    wiki = gollum(packet)
    path = opts[:path] || packet['route.resource_path'] || "Home"
    if packet.request.post?
      name   = path
      wiki   = gollum(packet)
      page   = wiki.page(name)
      format = "markdown".intern
      name   = packet.request.params["rename"] if packet.request.params["rename"]

      wiki.update_page(page, name, format, packet.request.params["content"], commit_message(packet))

      packet.reroute(wiki_url(packet) + ::Gollum::Page.cname(name))
    elsif page = wiki.page(path)
        opts[:page] = page
        opts[:name] = path
        opts[:title] = path.gsub('-', ' ')
        opts[:content] = page.raw_data
        do_view(packet, :edit, opts)
    else
      packet.reroute(wiki_url(packet))
    end
  end
  
  def history(packet, opts = {})
    opts.with_defaults!(packet.request.params)
    opts[:path] ||= (packet['route.resource_path'] || "Home")
    opts[:name] = opts[:path]
    opts[:page] ||= gollum(packet).page(opts[:path])
    opts[:page_num] = [opts[:page_num].to_i, 1, opts.delete("page_num").to_i].max
    page = opts[:page]
    versions = page.versions :page => opts[:page_num]
    
    i = versions.size + 1
    opts[:versions] = versions.map do |v|
        i -= 1
        { :id       => v.id,
          :id7      => v.id[0..6],
          :num      => i,
          :selected => page.version.id == v.id,
          :author   => v.author.name,
          :message  => v.message,
          :date     => v.committed_date.strftime("%B %d, %Y"),
          :gravatar => Digest::MD5.hexdigest(v.author.email) }
    end
    opts[:title] = opts[:path].gsub('-', ' ')
    do_view(packet, :history, opts)
  end
  
  def compare(packet, opts = {})
    opts = Mash.new(opts.with_defaults(packet.request.params))
    if packet.request.post?
      versions = opts[:versions] || []
      name = opts[:path]
      if versions.size < 2
        packet.reroute(wiki_url(packet) + 'history/'+::Gollum::Page.cname(name))
      else
        packet.reroute(wiki_url(packet) + 'compare/'+::Gollum::Page.cname(name) + '/' + versions.last + '...' + versions.first)
      end
    else
      parts = opts[:path].split('/')
      version_list = parts.pop
      opts[:path] = parts.join('/')
      name = opts[:path] || opts[:name]
      opts[:version_list] ||= version_list 
      opts[:versions] = opts[:version_list].split(/\.{2,3}/)
      opts[:name] = name
      opts[:page] ||= gollum(packet).page(name)
      diffs = gollum(packet).repo.diff(opts[:versions].first, opts[:versions].last, opts[:page].path)
      opts[:diff] = diffs.first
      opts[:lines] = lines_for_diff(diffs.first)
      do_view(packet, :compare, opts)
    end
  end
  
  def show(packet, opts = {})
    path = opts[:path] || packet['route.resource_path'] || "Home"
    path = path.gsub(/^\//, "") if path =~ /^\//
    wiki = gollum(packet)
    if page = wiki.page(path)
      opts[:page] = page
      opts[:name] = path
      opts[:title] = path.gsub('-', ' ')
      opts[:content] = page.formatted_data
      do_view(packet, :show, opts)
    elsif file = wiki.file(path)
      packet["template.disable"] = true
      file.raw_data
    else
      opts[:name] = path
      opts[:title] = path.gsub('-', ' ')
      create(packet, opts)
    end
  end
  
  def preview(packet, opts = {})
    data = packet.request.params['text']
    packet.markdown(gollum(packet).preview_page("Preview", data, "markdown").formatted_data)
  end
  
  def lines_for_diff(diff)
    lines = []
    left_line = right_line = nil
    diff.diff.split("\n")[2..-1].each_with_index do |line, line_index|
      left_line, current_line, left = left_diff_line_number(id, line, left_line, current_line)
      right_line, current_line, right = right_diff_line_number(id, line, right_line, current_line)
      lines << { :line => line,
                 :class => line_class(line),
                 :ldln => left,
                 :rdln => right }
    end
    lines
  end

  def line_class(line)
    if line =~ /^@@/
      'gc'
    elsif line =~ /^\+/
      'gi'
    elsif line =~ /^\-/
      'gd'
    else
      ''
    end
  end

  def left_diff_line_number(id, line, left_diff_line, current_line_number)
    if line =~ /^@@/
      m, li = *line.match(/\-(\d+)/)
      left_diff_line = li.to_i
      current_line_number = left_diff_line
      ret = '...'
    elsif line[0] == ?-
      ret = left_diff_line.to_s
      left_diff_line += 1
      current_line_number = left_diff_line - 1
    elsif line[0] == ?+
      ret = ' '
    else
      ret = left_diff_line.to_s
      left_diff_line += 1
      current_line_number = left_diff_line - 1
    end
    [left_diff_line,current_line_number,ret]
  end

  def right_diff_line_number(id, line, right_diff_line_number, current_line_number)
    if line =~ /^@@/
      m, ri = *line.match(/\+(\d+)/)
      right_diff_line_number = ri.to_i
      current_line_number = right_diff_line_number
      ret = '...'
    elsif line[0] == ?-
      ret = ' '
    elsif line[0] == ?+
      ret = right_diff_line_number.to_s
      right_diff_line_number += 1
      current_line_number = right_diff_line_number - 1
    else
      ret = right_diff_line_number.to_s
      right_diff_line_number += 1
      current_line_number = right_diff_line_number - 1
    end
    [right_diff_line_number,current_line_number,ret]
  end
end