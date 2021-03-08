require 'json'
require 'down'
require 'fileutils'
require 'date'

Jekyll::Hooks.register :site, :after_init do |site|
  puts "Cleaning #{site.config['mobilizon_cachedir']} folder"
  FileUtils.rm_rf(site.config['mobilizon_cachedir'])
end

module Jekyll

  class MobilizonAgenda < Liquid::Block

    def initialize(tag_name, markup, parse_context)
      super
      @markup = markup
      @attributes = {}

    end

    def fetch_and_thumbnail_image(site, url, cache_dir)
      cache_name = url.gsub /[\ :\/\?=]+/, '_'
      cache_dir_media = File.join cache_dir, 'media'
      cache_path = File.join cache_dir_media, cache_name

      if File.exist? cache_path
        return
      end

      tempfile = Down.download(url)

      puts "Thumbnailing #{cache_name}"

      image = MiniMagick::Image.open(tempfile.path)

      # Always strip meta
      image.strip
      image.resize "540x300^" # au moins 540 en largeur et 300 en hauteur

      FileUtils.mkdir_p cache_dir_media unless Dir.exists? cache_dir_media
      image.write cache_path

      # https://stackoverflow.com/questions/12124821/how-to-generate-files-from-liquid-blocks-in-jekyll
      #  Et https://patmurray.co/words/jekyll-open-graph-images
      # Add the file to the list of static_files needed to be copied to the _site
      site.static_files << Jekyll::StaticFile.new(site, site.source, File.join(site.config['mobilizon_cachedir'], 'media'), cache_name)
    end # def fetch_and_thumbnail_image

    def fetch_mobilizon(url, groups)
      puts "Mobilizon crawler \n"

      client = Graphlient::Client.new(url,
        headers: {
        },
        http_options: {
          read_timeout: 20,
          write_timeout: 30
        }
      )

      $today = DateTime.now().iso8601(2)

      $events = Array.new()
      for $group in groups
        query_nb_events = client.parse <<~GRAPHQL
        query($group: String!) {
          group(preferredUsername: $group) {
            organizedEvents {
              total,
            }
          }
        }
        GRAPHQL
        response = client.execute query_nb_events, group: $group
        $nb_events = response.data.group.organized_events.total
        if $nb_events == 0
          next
        end

        $nb_pages = ($nb_events / 10.0).ceil

        for $page in 1..$nb_pages

          query = client.parse <<~GRAPHQL
          query($page: Int, $group: String!, $afterDatetime: DateTime) {
            group(preferredUsername: $group) {
              organizedEvents(page: $page, afterDatetime: $afterDatetime){
                elements {
                  title,
                  url,
                  beginsOn,
                  endsOn,
                  options {
                    showStartTime,
                    showEndTime,
                  },
                  attributedTo {
                    avatar {
                      url,
                    }
                    name,
                    preferredUsername,
                  },
                  description,
                  onlineAddress,
                  physicalAddress {
                    locality,
                    description,
                    region
                  },
                  tags {
                    title,
                    id,
                    slug
                  },
                  picture {
                    url
                	},
                },
              }
            }
          }
          GRAPHQL

          response = client.execute query, page: $page, group: $group, afterDatetime: $today

          for $event in response.data.group.organized_events.elements
            $events.push $event.to_h
          end
        end
      end
      $size = $events.size
      puts "Crawling ended: #$size events crawled"
      return $events
    end # def

    def fetch_ics_event(site, url, cache_dir)
      cache_name = url.gsub /[\ :\/\?=]+/, '_'

      cache_path = File.join cache_dir, '_ics', cache_name

      if !File.exist? cache_path
        puts "Fetching ics #{url}"
        tempfile = Down.download(url)
        FileUtils.mkdir_p (cache_dir + '/_ics') unless Dir.exists? (cache_dir + '/_ics')
        FileUtils.mv tempfile.path, cache_path
      end

      cal_file = File.open cache_path

      cals = Icalendar::Calendar.parse cal_file
      cal = cals.first
      event = cal.events.first
      event
    end # def fetch_or_

    def create_icalendar(site, events, pageUrl)

      cache_dir = File.join site.source, site.config['mobilizon_cachedir']
      filename = pageUrl[1..-2].gsub(/[:\/]+/, '_') + '.ics'
      cache_path = File.join cache_dir, 'calendar', filename
      if File.exist? cache_path
        return
      end

      puts "Creating icalendar for #{pageUrl}"
      cal = Icalendar::Calendar.new

      # ugly
      cal.timezone do |t|
        t.tzid = "Europe/Paris"

        t.daylight do |d|
          d.tzoffsetfrom = "+0100"
          d.tzoffsetto   = "+0200"
          d.tzname       = "CEST"
          d.dtstart      = "19700329T020000"
          d.rrule        = "FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU"
        end

        t.standard do |s|
          s.tzoffsetfrom = "+0200"
          s.tzoffsetto   = "+0100"
          s.tzname       = "CET"
          s.dtstart      = "19701025T030000"
          s.rrule        = "FREQ=YEARLY;BYMONTH=01;BYDAY=1SU"
        end
      end

      for $event in events
        if $event['url']
          cal.events.push fetch_ics_event(site, $event['url'] + '/export/ics', cache_dir)
        end
      end

      cache_dir = File.join cache_dir, 'calendar'
      FileUtils.mkdir_p cache_dir unless Dir.exists? cache_dir

      File.open(cache_path, 'w') { |file|
        file.write cal.to_ical
      }

      site.static_files << Jekyll::StaticFile.new(site, site.source, File.join(site.config['mobilizon_cachedir'], 'calendar'), filename)
    end

    def fetch_or_get_cached_events(site)

      cache_dir = File.join site.source, site.config['mobilizon_cachedir']

      url = site.config["mobilizon_url"] + "/api"
      cache_name = url.gsub /[:\/]+/, '_'
      cache_dir_requests = File.join cache_dir, '_requests'
      cache_path = File.join cache_dir_requests, cache_name

      if File.exist? cache_path
        file = File.open(cache_path)
        cache = JSON.load file
        file.close
      else
        cache = fetch_mobilizon(url, site.config['mobilizon_whitelist'])
        FileUtils.mkdir_p cache_dir_requests unless Dir.exists? cache_dir_requests
        File.open(cache_path, 'w') { |file|
          file.write JSON.pretty_generate(cache)
        }
        file= File.open(cache_path)
        cache = JSON.load file

        for $event in cache
          if $event['picture']
            fetch_and_thumbnail_image(site, $event['picture']['url'], cache_dir)
          end
          if $event['attributedTo']['avatar']
            fetch_and_thumbnail_image(site, $event['attributedTo']['avatar']['url'], cache_dir)
          end
        end
      end

      return cache
    end # def generate

    def filter_events(events, tags_and_organizers)
      return events.select { |event| (tags_and_organizers.include? event['attributedTo']['preferredUsername']) || !(tags_and_organizers & (event['tags'].map { |tag| tag['slug'].downcase })).empty? || !(tags_and_organizers & (event['tags'].map { |tag| tag['title'].downcase })).empty? }
    end # def filter_events

    def change_to_timezone(string_date, timezone)
      date = DateTime.iso8601(string_date)
        .in_time_zone(timezone)
      date.iso8601(2)
    end

    def render(context)
      context.registers[:ical] ||= Hash.new(0)

      result = []
      context.stack do
        site = context.registers[:site]
        return unless site.config['mobilizon_fetch'] == true
        tags_and_organizers = context[@markup.strip()].split(',').map{ |tag|tag.downcase }

        events = fetch_or_get_cached_events(site)

        events = filter_events(events, tags_and_organizers)
        events = events.sort_by{ |event| event['beginsOn'] }

        create_icalendar(site, events, context.registers[:page]['url'])

        event_count = events.length
        if event_count == 0
          context["forloop"] = {
            "name" => "ical",
            "length" => event_count,
            "index" => 1,
            "index0" => 0,
            "rindex" => event_count,
            "rindex0" => event_count - 1,
            "first" => true,
            "last" => true,
          }
          result << nodelist.map do |n|
            if n.respond_to? :render
              n.render(context)
            else
              n
            end
          end.join
        end

        events.each_with_index do |event, index|
          context["event"] = event
          context["event"]["index"] = index
          if context["event"]["options"]["showStartTime"]
             context["event"]["beginsOn"] = change_to_timezone context["event"]["beginsOn"], site.config["mobilizon_timezone"]
           else
             context["event"]["beginsOn"] = context["event"]["beginsOn"].split('T')[0]
          end
          if context["event"]["options"]["showEndTime"]
             context["event"]["endsOn"] = change_to_timezone context["event"]["endsOn"], site.config["mobilizon_timezone"]
           else
             context["event"]["endsOn"] = context["event"]["endsOn"].split('T')[0]
          end

          if context["event"]["picture"]
            context["event"]["thumbnailurl"] = URI::encode(File.join site.config['mobilizon_cachedir'], "media", context["event"]["picture"]["url"].gsub(/[\ :\/\?=]+/, '_'))
          end
          if context["event"]["physicalAddress"] && context["event"]["physicalAddress"]["locality"]
            if context["event"]["physicalAddress"]["description"] == context["event"]["physicalAddress"]["locality"]
              context["event"]["location"] = context["event"]["physicalAddress"]["locality"] + ", " + context["event"]["physicalAddress"]["region"]
            else
              context["event"]["location"] = context["event"]["physicalAddress"]["description"] + ", " + context["event"]["physicalAddress"]["locality"] + ", " + context["event"]["physicalAddress"]["region"]
            end
          end
          if context["event"]["attributedTo"] && context["event"]["attributedTo"]["avatar"] && context["event"]["attributedTo"]["avatar"]["url"]
            context["event"]["organizerAvatar"] = URI::encode(
                File.join(site.config['mobilizon_cachedir'],
                  "media",
                  context["event"]["attributedTo"]["avatar"]["url"].gsub(/[\ :\/\?=]+/, '_')
                  )
                )
          end
          if context["event"]["attributedTo"] && context["event"]["attributedTo"]["name"]
            context["event"]["organizer"] = context["event"]["attributedTo"]["name"]
            context["event"]["groupUrl"] = site.config['mobilizon_url'] + '/@' + context["event"]["attributedTo"]["preferredUsername"]
          end

          context["forloop"] = {
            "name" => "ical",
            "length" => event_count,
            "index" => index + 1,
            "index0" => index,
            "rindex" => event_count - index,
            "rindex0" => event_count - index - 1,
            "first" => (index == 0),
            "last" => (index == event_count - 1),
          }

          result << nodelist.map do |n|
            if n.respond_to? :render
              n.render(context)
            else
              n
            end
          end.join
        end
      end # context stack
      result
    end # def render
  end
end

Liquid::Template.register_tag('mobilizonAgenda',   Jekyll::MobilizonAgenda)
