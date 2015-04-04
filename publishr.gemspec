# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "publishr/version"

Gem::Specification.new do |s|
  s.name        = "publishr"
  s.version     = Publishr::VERSION
  s.authors     = ["Michael Franzl"]
  s.email       = ["office@michaelfranzl.com"]
  s.homepage    = "http://red-e.eu/app/publishr"
  s.summary     = %q{Rapid publishing for ebooks, paper and the web}
  s.description = %q{Generates mobi files for Kindle, ebook files for other ebook readers, PDF via LaTex, and static webpages via webgen, all specified by a well-structured file system consisting of plain-text kramdown (a great flavour of Markdown) text files, as well as images.}
  s.rubyforge_project = "publishr"
  s.license = 'GPLv3'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_runtime_dependency "webgen", "0.5.17"
  s.add_runtime_dependency "kramdown"
  s.add_runtime_dependency "sanitize"
  s.add_runtime_dependency "nokogiri"
  s.add_runtime_dependency "unicode_utils"
  s.add_runtime_dependency "bibtex-ruby"
  s.add_runtime_dependency "citeproc-ruby"
  s.add_runtime_dependency "execjs"
  s.add_runtime_dependency "zip"
end
