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
  class LatexRenderer
    def initialize(path, metadata, language=nil)
      @name = File.basename(path)
      @language = language
      @inpath = path
      @outpath = File.join(@inpath,'latex')
      @gempath = Publishr::Project.gempath
      @metadata = metadata
    end

    def render
      make_tex_directory_structure
      render_tex
    end

    def make_tex_directory_structure
      FileUtils.mkdir_p @outpath
      Helper.copy_images(@inpath, @outpath, @language, 'jpg')
      Helper.copy_images(@inpath, @outpath, @language, 'eps')
      Helper.copy_images(@inpath, @outpath, @language, 'pdf')
      book_tex = File.join(@gempath,'lib','tex_templates',"book#{ @language }.tex")
      FileUtils.cp_r(book_tex, @outpath) if File.exists?(book_tex)
      FileUtils.cp_r Dir[File.join(@inpath,"*#{ @language }.tex")], @outpath
      FileUtils.cp_r Dir[File.join(@inpath,"*#{ @language }.bib")], @outpath
    end

    def render_tex
      infiles = Dir[File.join(@inpath, "*#{ @language }.txt"), File.join(@inpath, "*#{ @language }.page")]
      infiles.each do |infilepath|
        next if infilepath.include?("indexterms")
        content = File.open(infilepath, 'r').read
        if infilepath.include? '.page'
          kramdown = Helper.strip_webgen_header_from_page_file(content)
        else
          kramdown = content
        end
        latex = Kramdown::Document.new(kramdown, @metadata['kramdown_options']).to_latex
        fixed_latex = LatexProcessor.new(@inpath, @outpath, File.basename(infilepath), @language).process(latex, File.basename(infilepath))
        outfilepath = File.join(@outpath, File.basename(infilepath).gsub(/(.*).(txt|page)/, '\1.tex'))
        File.open(outfilepath, 'w'){ |f| f.write fixed_latex }
      end
    end
  end
end
