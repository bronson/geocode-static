require 'spec_helper'
require 'geolocal/provider/db_ip'

describe Geolocal::Provider::DB_IP do
  let(:it) { described_class }
  let(:provider) { it.new }


  describe 'network operation' do
    let(:country_page) {
      <<-eol
        <div class="container">
          <h3>Free database download</h3>
          <a href='http://download.db-ip.com/free/dbip-country-2015-02.csv.gz' class='btn btn-primary'>Download free IP-country database</a> (CSV, February 2015)
        </div>
      eol
    }

    # todo: would be nice to test returning lots of little chunks
    let(:country_csv) {
      <<-eol.gsub(/^\s*/, '')
        "0.0.0.0","0.255.255.255","US"
        "1.0.0.0","1.0.0.255","AU"
        "1.0.1.0","1.0.3.255","CN"
      eol
    }

    before do
      stub_request(:get, 'https://db-ip.com/db/download/country').
        with(headers: {'Accept'=>'*/*', 'User-Agent'=>'Ruby'}).
        to_return(status: 200, body: country_page, headers: {})

      stub_request(:get, "http://download.db-ip.com/free/dbip-country-2015-02.csv.gz").
        with(:headers => {'Accept'=>'*/*', 'User-Agent'=>'Ruby'}).
        to_return(:status => 200, :body => country_csv, :headers => {'Content-Length' => country_csv.length})
    end

    it 'can download the csv' do
      # wow!!  can't do this in an around hook because it gets the ordering completely wrong.
      # since around hooks wrap ALL before hooks, they end up using the previous test's config.
      if File.exist?(provider.csv_file)
        File.delete(provider.csv_file)
      end

      provider.download
      expect(File.read provider.csv_file).to eq country_csv

      File.delete(provider.csv_file)
    end
  end


  describe 'generating' do
    let(:example_output) {
      <<EOL
# This file is autogenerated

# Defines Geolocal::us, Geolocal::au
#     and Geolocal.in_us?, Geolocal.in_au?

module Geolocal
  def self.in_us? addr
    num = addr.to_i
    US.bsearch { |range| num > range.max ? 1 : num < range.min ? -1 : 0 }
  end
  def self.in_au? addr
    num = addr.to_i
    AU.bsearch { |range| num > range.max ? 1 : num < range.min ? -1 : 0 }
  end
end

Geolocal::US = [
0..16777215,
]

Geolocal::AU = [
16777216..16777471,
]

EOL
    }

    it 'can generate countries from a csv' do
      outfile = 'tmp/geolocal.rb'
      if File.exist?(outfile)
        File.delete(outfile)
      end

      Geolocal.configure do |config|
        config.tmpdir = 'spec/data'
        config.file = outfile
        config.countries = { us: 'US', au: 'AU' }
      end
      provider.update
      expect(File.read outfile).to eq example_output
      File.delete(outfile)
    end
  end
end