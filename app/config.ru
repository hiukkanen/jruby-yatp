require 'json'
require 'nokogiri'

XSL = <<~XSL
  <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="text"/>
    <xsl:template match="/"><xsl:for-each select="//item"><xsl:value-of select="."/>;</xsl:for-each></xsl:template>
  </xsl:stylesheet>
XSL

def respond(status, body)
  [status, { 'content-type' => 'application/json' }, [JSON.generate(body)]]
end

def versions
  {
    jruby: JRUBY_VERSION,
    ruby: RUBY_VERSION,
    java: Java::JavaLang::System.getProperty('java.version'),
    nokogiri: Nokogiri::VERSION,
    jruby_rack: (defined?(JRuby::Rack::VERSION) ? JRuby::Rack::VERSION : nil),
    rack: (Rack.release rescue nil)
  }
end

def nokogiri_checks
  xml  = Nokogiri::XML('<root><item id="1">a</item><item id="2">b</item></root>')
  html = Nokogiri::HTML('<html><body><p class="x">hi</p></body></html>')
  {
    xml_xpath: xml.xpath('//item').map { |n| n['id'] } == %w[1 2],
    html_css:  html.at_css('p.x')&.text == 'hi',
    builder:   Nokogiri::XML::Builder.new { |x| x.a { x.b 'c' } }.to_xml.include?('<b>c</b>'),
    xslt:      Nokogiri::XSLT(XSL).apply_to(xml) == 'a;b;'
  }
end

run lambda { |env|
  case env['PATH_INFO']
  when '/health'
    respond 200, status: 'ok', versions: versions
  when '/nokogiri'
    checks = nokogiri_checks
    respond(checks.values.all? ? 200 : 500, checks: checks, versions: versions)
  else
    respond 404, error: 'not found'
  end
}
