require 'rubygems'
require 'data_mapper'

DataMapper.setup :default, settings.db

class Code
    include DataMapper::Resource

    property :id,         Serial
    property :code,       String, :required => true, :unique => true
    property :created_at, DateTime

    has n, :downloads, :through => :code_downloads
end

class Download
    include DataMapper::Resource

    property :id,          Serial
    property :title,       String
    property :artwork,     String
    property :description, String
    
    property :path,        String
    property :format,      String
    property :storage,     String

    has n, :codes, :through => :code_downloads
    has n, :download_logs
end

class CodeDownload
    include DataMapper::Resource

    property :count, Integer, :default => 0

    belongs_to :code, :key => true
    belongs_to :download, :key => true
end

class DownloadLog
    include DataMapper::Resource

    belongs_to :download, :key => true

    property :id,         Serial
    property :code,       String
    property :ip_address, String
    property :email,      String
    property :contact,    Integer, :default => 0
    property :format,     String
    property :timestamp,  DateTime
end

DataMapper.finalize

DataMapper.auto_upgrade!
