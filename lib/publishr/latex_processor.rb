# Encoding: UTF-8

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

  # this class is mainly responsible for transforming Publishr's superset of Kramdown (which is copied plainly into LaTeX format by Kramdown, see method render_tex in LatexRenderer) into corresponding LaTeX commands, most notably the CITE syntax and the INDEX syntax. It also cleans up LaTeX syntax as outputted by Kramdown. It is used by the LatexRenderer class of this module.
  class LatexProcessor
    def initialize(inpath, outpath, file, language)
      @line = ''
      @inpath = inpath
      @file = file
      @outpath = outpath

      # set language
      # inside of the whole publishr gem, @language must be prefixed with a dot
      if language and not language.empty?
        @language = language.include?('.') ? language : ".#{language}" # inside of the whole publishr gem, @language must be prefixed with a dot
      else
        @language = nil
      end

      #Dir.chdir @inpath

      # user-defined content filtering
      filter_filepath = File.join(@inpath,"filter#{ @language }.js")
      if File.exists?(filter_filepath)
        filter_code = "(function() { var filters = {};"
        filter_code += File.read(filter_filepath)
        filter_code += "\nreturn filters;})()"
        @v8_object = ExecJS.eval(filter_code)
      end

      # state machine variables
      @imagewidth = nil
      @vspace = nil
      @wrapfigure_state = nil
      @scfigure_state = nil

      # initialize image paths. only jpg and eps are supported
      @images = Dir[File.join(@inpath, 'images', "*.jpg")]
      @images = @images.collect{ |i| File.basename(i) }
      @images_eps = Dir[File.join(@inpath, 'images', "*.eps")]
      @images_eps = @images_eps.collect{ |i| File.basename(i) }

      # initialize index terms
      indextermfile = File.join(@inpath, "indexterms#{ @language }.txt")
      if File.exists?(indextermfile)
        indexterms = File.read(indextermfile).split("\n").uniq.sort_by{ |j| j.split(">").first.length }
        @index_terms = []
        indexterms.each do |line|
          next if line[0] == "#" or line.strip.empty?
          searchreplaceterms = line.split(">")
          @index_terms << searchreplaceterms
        end
      end
    end

    def process(latex, filename)
      @lines = latex.split("\n")
      processed_lines = []
      @lines.each do |l|
        @line = l
        unless @line.strip.empty? # speed improvement
          transform_kramdown_superset
          cleanup
          transform_images
          translate_image
          if @index_terms
            set_index
          end
        end
        processed_lines << @line
      end

      processed_lines = processed_lines.join("\n")
      if @v8_object
        processed_lines = run_custom_filter(processed_lines, filename)
      end
      return processed_lines
    end

    private

    def cleanup
      @line.gsub! /.hypertarget{.*?}{}/, ''
      @line.gsub! /.label{.*?}/, ''

      # fix LaTeX quirk with certain quotes combined with ! or ?
      @line.gsub! '!', '!{}'
      @line.gsub! '?', '?{}'

      # use correct latex hyphen code for better automatic hyphenation
      @line.gsub! /(\w)-(\w)/, '\1\\hyp{}\2'

      @line.gsub! '°',  '\\textdegree'

      # improve typography: separate thousands, beginning with 10000
      @line.gsub! /(\d\d)(\d\d\d)([^\d])/, '\1\\,\2\3'

      # avoid break between ellipsis and word
      @line.gsub! /(\w \\ldots{})/, '\\mbox{\1}'

      # set better spacing for [...]
      @line.gsub! /\[\\ldots{}\]/, '\\omission{}'
    end

    def transform_kramdown_superset
      # better formatting for names, book titles and technical terms
      @line.gsub! /name\((.*?)\)/,    '\name{\1}'
      @line.gsub! /title\((.*?)\)/,   '\book{\1}'
      @line.gsub! /opentype\((.*?)\)/,'\begin{opentype}\1\end{opentype}'
      @line.gsub! /{\\tt (.*?)}/,     '\object{\1}'

      if @line.include?("quot")
        # set special attributes to quotation like environments
        @line.gsub! /{quot(.*?)}   %  class="(.*?)"/, '{quot\1\2}'
        @line.gsub! /{quote}/,                        '{quotenormal}'
        @line.gsub! /{quotation}/,                    '{quotationnormal}'
      end

      # for regular # headings, set the page header. this requires \pagestyle{scrheadings} in the preamble
      @line.gsub!(/\\chapter{([^*])(.+)}/) { "\\chapter{#{ $1 }#{ $2 }}\n\n\\rohead{\\headmark}" }

      # for #* headings: add a manual TOC entry (which is not enumerated) and a manual page header
      @line.gsub!(/\\chapter{\* (.+)}/) { "\\chapter*{#{ $1 }}\n\n\\addcontentsline{toc}{chapter}{#{ $1 }}\n\n\\rohead{#{ $1 }}" }

      # CITE syntax
      if @line.include?("CITE")
        @line.gsub!  /\sCITE([(\[{])(.*?)}/, '\autocite\1\2}'
        @line.gsub! /\sCITES([(\[{])(.*?)}/, '\autocites\1\2}'
        @line.gsub! '\{', "{"
        @line.gsub! '\}', "}"
      end

      # transform special kramdown comments (begin with a backslash) into real latex commands
      @line.gsub! /% (\\.*)/, '\1'

      # superscript
      @line.gsub! /\\\^{}(.*?)\\\^{}/, '\\textsuperscript{\1}'
    end

    def set_index
      current_index = 0
      matched_indexes = []
      @index_terms.each do |t|
        regex = t[0]
        match = /#{ regex }/.match(@line)
        matched_string = match[0] if match
        if matched_string
          matched_indexes << current_index
          @line.sub! matched_string, "#{ matched_string }INDEX{#{ current_index }}"
        end
        current_index += 1
      end

      matched_indexes.each do |i|
        @line.sub! "INDEX{#{ i }}", "\\index{#{ @index_terms[i][1].nil? ? @index_terms[i][0] : @index_terms[i][1] }}"
      end
    end

    def transform_images
      # detect if either a width or a class attribute has been specified for images
      match = /begin{figure}   %  (.*)/.match @line
      if match
        attributestring = match[1]
        if attributestring.include?('width')
          @imagewidth = /width="(.*?)"/.match(attributestring)[1]
          # remember this value for the following lines, kinda state machine. The width has to be set as attribute to the includegraphics command. see below.
        end
        if attributestring.include?('vspace')
          @vspace = /vspace="(.*?)"/.match(attributestring)[1]
        end
        if attributestring.include?('class')
          cls = /class="(.*)"/.match(attributestring)[1]
          if cls[0] == "W"
            # wrapfigure has been specified by the user
            wrapfiguretype = cls[1] ? cls[1] : 'O'
            @line.gsub! 'begin{figure}', "begin{wrapfigure}{#{ wrapfiguretype }}{#{ @imagewidth.to_f/100.0 }\\textwidth}\n"
            if @vspace
              @line += "\n\\vspace{#{ @vspace }}\n"
            end
            @wrapfigure_state = true
          elsif cls[0] == "H" or cls[0] == "h"
            # place figure exactly here
            @line.gsub! 'begin{figure}', "begin{figure}[#{ cls[0] }]"
          elsif cls[0] == "S"
            # sidecap
            @line.gsub! 'begin{figure}', 'begin{SCfigure}'
            @scfigure_state = true
          end
        end
      end

      # statemachine: set the width of the next includegraphics and forget last remembered width
      if @imagewidth and @line.include? 'includegraphics'
        @line.gsub!(/\\includegraphics{(.*?)}/){"\\includegraphics[width=#{ @imagewidth.to_f/100.0 }\\textwidth]{#{ $1 }}"}
        @imagewidth = nil
      end

      # statemachine: set the end of wrapfigure
      if @wrapfigure_state and @line.include? 'end{figure}'
        if @vspace
          @line = "\n\\vspace{#{ @vspace }}\n" + @line
        end
        @line.gsub! "end{figure}", "end{wrapfigure}"
        @wrapfigure_state = nil
        @vspace = nil
      end

      # statemachine: set the end of wrapfigure
      if @scfigure_state and @line.include? 'end{figure}'
        @line.gsub! "end{figure}", "end{SCfigure}"
        @scfigure_state = nil
      end
    end

    def translate_image
      # the user always enters the untranslated image name
      if @line.include?('includegraphics')
        #puts "includegraphics line is #{ @line }"
        entered_src = /includegraphics.*{(.*?)}/.match(@line)[1]
        #puts "entered_src is #{ entered_src }"
        translated_src_jpg = entered_src.gsub(/\.jpg/, "#{ @language }.jpg")
        #puts "translated_src_jpg is #{ translated_src_jpg }"
        # use the translated image instead, if found on filesystem. this was implemete to be consistent with webgen.
        translated_src_eps = entered_src.gsub(/\.jpg/, "#{ @language }.eps")
        #puts "translated_src_eps is #{ translated_src_eps }"
        #puts "@images_eps is #{ @images_eps.inspect }"
        if @images_eps.include?(translated_src_eps)
          rename_language = @language.gsub('.', '-')
          #puts "rename_language is #{ rename_language }"
          rename_filename = entered_src.gsub('.jpg', '') + rename_language + '.eps'
          if File.exists?(File.join(@outpath,translated_src_eps))
            #puts "renaming eps"
            # conditional, because it already could have been renamed
            FileUtils.mv File.join(@outpath,translated_src_eps), File.join(@outpath, rename_filename)
          end
          #puts "gsubbing @line #{ @line }, #{ rename_language }"
          #puts ""
          @line.gsub!(/\.jpg/, "#{ rename_language }")

        elsif @images.include?(translated_src_jpg)
          rename_language = @language.gsub('.', '-')
          #puts "rename_language is #{ rename_language }"
          rename_filename = entered_src.gsub('.jpg', '') + rename_language + '.jpg'
          #puts "rename_filename is #{ rename_filename }"
          if File.exists?(File.join(@outpath,translated_src_jpg))
            #puts "renaming"
            # conditional, because it already could have been renamed
            FileUtils.mv File.join(@outpath,translated_src_jpg), File.join(@outpath, rename_filename)
          end
          @line.gsub!(/\.jpg/, "#{ rename_language }")
        else
          @line.gsub! '.jpg', ''
        end
      end
    end

    def run_custom_filter(txt, filename)
      function = @v8_object['latex_postprocessing']
      return function.methodcall(function, txt, filename)
    end
  end
end
