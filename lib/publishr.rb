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

require 'webgen/website'
require 'kramdown'
require 'erb'
require 'yaml'
require 'fileutils'
require 'sanitize'
require 'nokogiri'
require 'unicode_utils/upcase'
require 'citeproc'
require 'execjs'
require 'bibtex'

dir = File.dirname(__FILE__)
Dir[File.expand_path("#{dir}/publishr/*.rb")].uniq.each do |file|
  require file
end


# overrides for kramdown

module Kramdown
  module Converter
    class Latex
      #puts ENTITY_CONV_TABLE.inspect
      # output og and fg instead of guillemot
      ENTITY_CONV_TABLE[171] = ['\og{}']
      ENTITY_CONV_TABLE[187] = ['\fg{}']

      TABLE_ALIGNMENT_CHAR[:default] = 'p{1in}'
    end
  end
end
