# encoding: UTF-8

# PublishR -- Rapid publishing for ebooks (epub, Kindle), paper (LaTeX) and the web (webgen)'
# Copyright (C) 2012 Red (E) Tools Ltd. (www.red-e.eu)
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
# 
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

module Publishr
  
  # this standalone class is mainly responsible for optimizing html for mobile ebook readers. It is used by publishr_web for its preview window and by the EbookRenderer class of this module.
  class HtmlProcessor
    def initialize(inpath='', metadata={}, language=nil, rails_resources_url='')
      @line = ''
      @inpath = inpath
      @metadata = metadata
      @rails_resources_url = rails_resources_url
      
      # set language
      # inside of the whole publishr gem, @language must be prefixed with a dot
      if language and not language.empty?
        @language = language.include?('.') ? language : ".#{language}" 
      else
        @language = nil
      end
      
      # user-defined content filtering
      filter_filepath = File.join(@inpath,"filter#{ @language }.js")
      if File.exists?(filter_filepath)
        @v8_context = V8::Context.new
        filter_code = "(function() { var filters = {};"
        filter_code += File.read(filter_filepath)
        filter_code += "\nreturn filters;})()"
        @v8_object = @v8_context.eval(filter_code)
      end
     
      # initialize image paths
      @images = Dir[File.join(@inpath, 'images', "*.jpg")]
      @images = @images.collect{ |i| File.basename(i) }

      # statemachine states
      @depth = 0
      @quotetype = nil
      @add_footnote = false
      @process_footnotes = false
      @footnote_number = 0
      @footnote_reference = ''
    end
    
    def transform_for_ebook(html, filename)
      @lines = html.split("\n")
      output = []
      @lines.each do |l|
        @line = l
        process_line
        output << @line
      end
      output = output.join("\n")
      if @v8_object
        output = run_custom_filter(output, filename)
      end
      return output
    end
    
    # public sanitize methods
    
    def sanitize(html)
      html = add_blockquotes(html) if @metadata[:start_quote_strings] and @metadata[:end_quote_strings]
      sanitized_html = Sanitize.clean(html, :elements => ['b','i','em','strong','code','br','var','p','blockquote','img','sup','sub'], :attributes => { 'img' => ['src', 'alt'] })
      return sanitized_html
    end
    
     # this function adds blockquote tags because .doc files uses arbitrary styles rather than HTML tags
    def add_blockquotes(html)
      @lines = html.split("\n")
      modified_lines = []
      quote_enabled = false
      @lines.each do |line|
        @line = line
        @line.gsub!('<br>', '</p><p>')
        found_quote_start = false
        @metadata[:start_quote_strings].each do |s|
          found_quote_start = @line.include?(s)
          break if found_quote_start == true
        end
        if not quote_enabled and found_quote_start
          modified_lines << "<blockquote>\n"
          quote_enabled = true
        end
        found_quote_end = false
        @metadata[:end_quote_strings].each do |s|
          found_quote_end = @line.include?(s)
          break if found_quote_end == true
        end
        if quote_enabled and found_quote_end
          modified_lines << "</blockquote>\n"
          quote_enabled = false
        end
        modified_lines << @line
      end
      return modified_lines.join("\n")
    end
    
    private
    
    def process_line
      set_statemachine_states
      transform_blockquotes
      transform_footnote_references
      improve_typography
      make_uppercase
      clean_star_header
      mark_merge_conflicts
      if @line.include?('<img')
        add_image_captions 
        translate_image
      end
      unless @rails_resources_url.to_s.empty?
        change_resources_url_for_rails
      end
      if @process_footnotes == true
        process_footnotes
      end
      if @add_footnote == true && @line.include?('<p>')
        add_footnote
      end
      if @process_footnotes == true && @line.include?('<p')
        make_footnote_paragraph
      end
    end
    
    def set_statemachine_states
      # state machine variables
      if @line.include?('<div class="footnotes">')
        @process_footnotes = true
      end
      
      if @process_footnotes == true && @line.include?('</div>')
        @process_footnotes = false
      end
      
      if @line.include?('<ol start=')
        # get the first footnote number
        match = /ol start=\"(.*?)\".*/.match(@line)
        if match
          @footnote_number = match[1].to_i - 1
        end
      end
      
      if @line.include?('<li id="fn')
        @add_footnote = true
        @footnote_number += 1
      end
    end
    
    # Kindle doesn't recognize <blockquote>, so add class to p tags depending on the blockquote depth
    def transform_blockquotes
      if @line.include?('<blockquote')
        # blockquote opening
        @depth += 1
        if @depth == 1
          @quotetype = /<blockquote class="(.*?)">/.match(@line)
        end
      end
      if @line.include?('</blockquote')
        # blockquote closing
        @depth -= 1
        if @depth.zero?
          @quotetype = nil
        end
      end
      unless @depth.zero?
        @line.gsub!(/<p/,"<p class=\"blockquote_#{ @quotetype[1] if @quotetype }_#{ @depth }\"")
        @line.gsub!(/<li/,"<li class=\"blockquote_#{ @quotetype[1] if @quotetype }_#{ @depth }\"")
        @line.gsub!(/<ul/,"<li class=\"blockquote_#{ @quotetype[1] if @quotetype }_#{ @depth }\"")
      end
    end
    
    def transform_footnote_references
      if @line.include? '<sup id="fnref'
        @line.gsub! /<sup id="fnref:.*?">/, ''
        @line.gsub! '</sup>', ''
        @line.gsub! /class=\"footnote\">(.*?)<\/a>/, '><sup> [\1]</sup></a>'
      end
      @line.gsub!(/(<div class=.footnotes.>)/){ "<br style='page-break-before:always;'>#{ $1 }<h4>#{ @metadata['footnote_heading'] }</h4>" }
    end
  
    def improve_typography
      if @metadata["ebook_format_upcase_title"] == true
        @line.gsub!(/title\((.*?)\)/) { "<span class=\"booktitle\">#{ UnicodeUtils.upcase($1) }</span>" }
      else
        @line.gsub!(/title\((.*?)\)/) { "<span class=\"booktitle\">#{ $1 }</span>" }
      end
      
      if @metadata["ebook_format_upcase_name"] == true
        @line.gsub!(/name\((.*?)\)/) { "<span class=\"authorname\">#{ UnicodeUtils.upcase($1) }</span>" }
      else
        @line.gsub!(/name\((.*?)\)/) { "<span class=\"authorname\">#{ $1 }</span>" }
      end
      
      @line.gsub!(/opentype\((.*?)\)/,'\1')
      @line.gsub! /\^(.*?)\^/, '<sup>\1</sup>'
    end

    # Kindle doesn't recognize text-transform: uppercase;
    def make_uppercase
      #if @metadata["ebook_format_author_upcase"] == true
      #  @line.gsub!(/<var>(.*?)<\/var>/){ "<var>#{ UnicodeUtils.upcase($1) }</var>" }
      #end
      @line.gsub!(/<h1(.*?)>(.*?)<\/h1>/){ "<h1#{ $1 }>#{ UnicodeUtils.upcase($2) }</h1><hr />" }
    end
    
    def clean_star_header
      @line.gsub!(/<h1(.+?)>\*(.+?)<\/h1>/) { "<h1#{ $1 }>#{ $2 }</h1>" }
    end
    
    def mark_merge_conflicts
     @line.gsub! /«««.*$/, '<span style="color:red;">'
     @line.gsub! '=======', '</span></p><p><span style="color:orange;">'
     @line.gsub! /»»».*$/, '</span></p>'
    end

    def add_image_captions
      @line.gsub! /<p(.*?)><img src="(.*?)" alt="(.*?)"(.*)\/><\/p>/, '<p class="image"><img src="\2"\1\4/><br /><code>\3</code></p>'
      @line.gsub! /width="(\d*).*?"/, 'width="\1%"'
    end
    
    def translate_image
      # the user always enters the untranslated image name
      entered_src = /src="(.*?)"/.match(@line)[1]
      translated_src = entered_src.gsub(/\.jpg/, "#{ @language }.jpg")
      # use the translated image instead, if found on filesystem. this was implemete to be consistent with webgen.
      @line.gsub!(/\.jpg/, "#{ @language }.jpg") if @images.include?(translated_src)
    end
    
    def process_footnotes
      @line.gsub!(/<p(.*?)>/){ "<p>" }
      @footnote_reference = /<li (id="fn.*")/.match(@line)[1] if @line.include?('<li id="fn')
      @line.gsub! /<li id="fn.*>/, ''
      @line.gsub! /<\/li>/, ''
      @line.gsub! /<ol.*?>/, ''
      @line.gsub! /<\/ol>/, ''
      @line.gsub! /<a href="#fnref.*<\/a>/, ''
    end
    
    # Kindle doesn't display <ol> list numbers when jumping to a footnote, so replace them with conventional text
    def add_footnote
      @line.gsub! /<p>/, "<hr><p #{ @footnote_reference }><b>[#{ @footnote_number }]</b>: "
      @add_footnote = false
    end
    
    def make_footnote_paragraph
      @line.gsub! /<p/, "<p class='footnote' "
    end
    
    def change_resources_url_for_rails
      # @rails_resources_url can point to a Rails controller which provides authentication, or to a location to the filesystem which the webserver has access to.
      if @line.include?(".jpg")
        @line.gsub!(/src="(.*?.jpg)/){ "src=\"#{ @rails_resources_url }#{ $1 }" }
      end
      
      # Transform .css links into inline CSS for local development since the webserver won't have access to the css file.
      if @line.include?("rel=\"stylesheet\"")
        internal_styleheetnames = ["epub.css", "preview.css"]
        internal_styleheetnames.each do |n|
          if @line.include?(n)
          # those always reside within the publishr gem
            dir = File.dirname(__FILE__)
            css_contents = File.read(File.expand_path("../epub_skeleton/#{ n }", dir))
            @line = "<style>" + css_contents + "</style>"
          end
        end
        
        # Include overriding localized .css in case it is present
        override_stylesheet_name = "override#{ @language }.css"
        if (
          @line.include?("override.css") &&
          File.exists?( File.join(@inpath, override_stylesheet_name) )
        )
          css_contents = File.read( File.join(@inpath, override_stylesheet_name) )
          @line = "<style>" + css_contents + "</style>"
        end
      end
    end
    
    def run_custom_filter(txt, filename)
      function = @v8_object['html_postprocessing']
      return function.methodcall(function, txt, filename)
    end
    
  end
end
