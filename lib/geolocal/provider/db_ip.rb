require 'geolocal/provider/base'

require 'csv'
require 'net/http'
require 'fileutils'
require 'zlib'


class Geolocal::Provider::DB_IP < Geolocal::Provider::Base
  START_URL = 'https://db-ip.com/db/download/country'

  # TODO: refactor progress and download code into a mixin?

  def update_download_status size, length
    @current_byte ||= 0
    @previous_print ||= 0
    @current_byte += size

    if length
      pct = @current_byte * 100 / length
      pct = (pct / 5) * 5

      if pct != @previous_print
        @previous_print = pct
        status pct.to_s + '% '
      end
    else
      # server didn't supply a length, display running byte count?
    end
  end

  def csv_file
    "#{config[:tmpdir]}/dbip-country.csv.gz"
  end

  def get_launch_page_body(start_url)
    begin
      uri = URI start_url
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE # Sets the HTTPS verify mode
      response = http.get(uri.request_uri)
      raise unless response.code.match(/^2/)
      response.body
        
    rescue
      raise "unable to access resource: #{START_URL}"
    end
  end

  def download_files
    # they update the file every month but no idea which day they upload it
    return if up_to_date?(csv_file, 86400)

    page = get_launch_page_body(START_URL)

    # if we used Nokogiri: (we don't since we don't want to force the dependency)
    # doc = Nokogiri::HTML(page)
    # href = URI doc.css('a.btn-primary').attr('href').to_s

    elem = page.match(/<a\b[^>]*class=['"][^'"]*btn-primary[^>]*>/) or
      raise "no <a class='btn-primary'> element found in #{START_URL}"
    attr = elem.to_s.match(/href=['"]([^'"]+)['"]/) or raise "no href found in #{elem}"
    href = URI attr[1]

    # stream result because it's large
    FileUtils.mkdir_p(config[:tmpdir])
    status "downloading #{href} to #{csv_file}\n"

    elapsed = time_block do
      File.open(csv_file, 'wb') do |file|
        Net::HTTP.new(href.host, href.port).request_get(href.path) do |response|
          total_length = response['Content-Length'].to_i
          status "  reading #{(total_length/1024.0/1024).round(1)} MB: "

          response.read_body do |chunk|
            file.write chunk
            update_download_status(chunk.length, total_length)
          end
        end
      end
    end

    status "\n  read #{@current_byte} bytes in #{elapsed.round(2)} seconds at " +
         "#{(@current_byte/1024/elapsed).round(1)} KB/sec\n"
  end

  # a bit of debugging code to print all non-matched country codes.  should be deleted one day.
  # The Countries gem doesn't know about these country codes from the csv: CS FX UK YU TP and blank
  def check_country_codes(countries, row)
    @known_codes ||= countries.reduce(Set.new) { |a,(_,v)| a.merge v; a }
    unless @known_codes.include?(row[2])
      puts "#{row[2]}: #{row[0]}..#{row[1]}"
    end
  end

  def read_ranges countries
    status "computing ranges\n"

    row_count = 0
    match_count = 0

    elapsed = time_block do
      File.open(csv_file, 'r') do |file|
        gz = Zlib::GzipReader.new(file)
        CSV.new(gz, headers: false).each do |row|
          row_count += 1
          countries.each do |name, country_codes|
            if country_codes.include?(row[2])
              match_count += 1
              yield name, row[0], row[1]
            end
            # check_country_codes(countries, row)
          end
        end
      end
    end

    status "  matched #{match_count} of #{row_count} ranges in #{elapsed.round(2)} seconds\n"
  end
end
