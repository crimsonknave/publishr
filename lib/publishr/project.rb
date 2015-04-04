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

  class Project
    def initialize(absolutepath, language=nil, absoluteconverterspath='', rails_resources_url='', book_source_file_path='', projectname='unnamed')
      Publishr.log "[Publishr::Project] initialize"
      @name = projectname
      if language and not language.empty?
        @language = language.include?('.') ? language : ".#{language}" # inside of the whole publishr gem, @language must be prefixed with a dot
      else
        @language = nil
      end
      @inpath = absolutepath
      @converterspath = absoluteconverterspath
      @rails_resources_url = rails_resources_url
      @book_source_file_path = book_source_file_path
      @gempath = Publishr::Project.gempath
      @metadata = {}
      @metadata = YAML::load(File.open(File.join(@inpath,"metadata#{@language}.yml"), 'r').read) if File.exists?(File.join(@inpath,"metadata#{@language}.yml"))
    end

    def self.gempath
      File.expand_path('../../../', __FILE__)
    end

    def make_ebook
      Publishr::Project.merge_bibliography_databases(@inpath, @language)

      Publishr.log "[Publishr::Project] make_ebook"
      ebook = EbookRenderer.new(@inpath, @metadata, @language, @rails_resources_url, @name)
      ebook.render
      Publishr.log "[Publishr::Project] make_ebook: calling kindlegen"
      if @converterspath and File.exists?(File.join(@converterspath,'kindlegen'))
        kindlegen = File.join(@converterspath,'kindlegen')
        epubfile = File.join(@inpath,"#{ @name }#{ @language }.epub")
        lines = []
        IO.popen("#{ kindlegen } -verbose #{ epubfile }") do |io|
          while (line = io.gets) do
            Publishr.log line
            lines << line
          end
        end
        lines.join('<br />')
      else
        Publishr.log 'path to kindlegen was not specified or binary not present. Not generating a Kindle .mobi file.'
      end
    end

    def make_pdf
      Publishr::Project.merge_bibliography_databases(@inpath, @language)

      pdf = LatexRenderer.new(@inpath, @metadata, @language)
      pdf.render

      outpath = File.join(@inpath,'latex')

      Dir.chdir outpath
      Dir['*.eps'].each do |f|
        `perl /usr/bin/epstopdf #{ f }`
        jpg_to_delete = File.basename(f).gsub(/(.*).eps/, '\1.jpg')
        FileUtils.rm jpg_to_delete if File.exists? jpg_to_delete
        FileUtils.rm f
      end

      log_lines = []

      `makeindex main#{ @language }.idx`

      if @metadata["latex_command"] == "xelatex"
        latex_command = "xelatex"
      else
        latex_command = "pdflatex"
      end

      IO.popen("#{ latex_command } -interaction=nonstopmode main#{ @language }.tex 2>&1") do |io|
        while (line = io.gets) do
          log_lines << line
        end
      end

      if (File.exists?("bibliography#{ @language }.bib"))
        `biber main#{ @language }`
      end

      FileUtils.mv(File.join(outpath,"main#{ @language }.pdf"), File.join(@inpath,"#{ @name }#{ @language }.pdf")) if File.exists?(File.join(outpath,"main#{ @language }.pdf"))

      return log_lines.join('<br />')
    end

    def make_web
      Dir.chdir @inpath
      #FileUtils.rm_rf 'out'
      site = Webgen::Website.new '.'
      site.init
      messages = site.render
      #FileUtils.rm_rf '.sass-cache'
      #FileUtils.rm_rf 'webgen.cache'
      `#{@gempath}/lib/webgen_postprocessing.sh out`

      configfile = File.join(@inpath, 'publishr_config.yml')
      if File.exists?(configfile)
        config = YAML::load(File.read(configfile))
        if config[:web_documentroot_copy] == true
          FileUtils.mkdir_p(config[:web_documentroot_path])
          FileUtils.cp_r(File.join(@inpath, 'out'), config[:web_documentroot_path])
        end
      end
      messages
    end

    def convert_book
      Dir.chdir @inpath
      source_html = File.open(@book_source_file_path, 'r'){ |f| f.read }
      Publishr::BookProcessor.new(@inpath, @metadata).import(source_html)
    end

    def self.merge_bibliography_databases(inpath, language)
      language = language.include?('.') ? language : ".#{language}"

      Dir.chdir inpath

      will_overwrite_file = false
      outputfile_name = "bibliography#{ language }.bib"
      if File.exists?(outputfile_name)
        outputfile_contents = File.readlines(outputfile_name)
        if outputfile_contents.first.include? "# autogenerated"
          will_overwrite_file = true
        end
      else
        will_overwrite_file = true
      end

      if will_overwrite_file == true
        bibfiles =  Dir["*#{ language }.bib"]

        bibfiles.delete("bibliography#{ language }.bib")

        output = "# autogenerated by concatenation of all *#{ language }.bib files in this directory. Do not edit this file manually, changes will be overwritten. Remove this line if you want to take control over this file.\n\n"

        bibfiles.each do |bibfile|
          output += File.read(bibfile)
        end

        File.write(outputfile_name, output)
        return true

      else
        return false
      end

    end
  end
end
