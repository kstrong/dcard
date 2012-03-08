require 'rubygems'
require 'zip/zip'
require 'mp3info'

archive = File.join(Dir.pwd, 'media', 'thought_and_memory.zip')
puts archive

Zip::ZipInputStream::open(archive) do |io|
    while (entry = io.get_next_entry)
        if File.extname(entry.name) == ".mp3"
            StringIO.open(io.read) do |sio|
                Mp3Info.open(sio) do |mp3|
                    puts mp3.tag.tracknum 
                    puts '. ' 
                    puts mp3.tag.artist 
                    puts ' - ' 
                    puts mp3.tag.album 
                    puts ' - ' 
                    puts mp3.tag.title 
                    length = mp3.length
                    lmin = (length / 60.0).to_i
                    lsec = length.to_i % 60
                    puts ' (' << lmin.to_s << ':' << lsec.to_s << ')'
                end
            end
        end
    end
end

#http://sox.sourceforge.net/
