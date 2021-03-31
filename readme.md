# Script to include Mobilizon into Jekyll-website

*This plugin is used in production since January 2021. Please contact me at contact@marc-antoinea.fr if needed.*

This plugin fetches incoming events for a list of groups in a given mobilizon instance (through graphql api).
Images are fetched too and thumbnailed with `minimagick`. It means that no requests are made to mobilizon except during website compilations.

You can create many agendas based on `groups` and `tags` through the `mobilizonAgenda` Jekyll-tag

**Example** You want to display all events from group `my-group` and all events with tag `my-tag` and all events with tag `my_awesome_tag` :
```html
{% assign options="my-group,my_tag,my_awesome_tag" %}
{% mobilizonAgenda options %}

{% if forloop.length == 0 %}
<p>We did not find any event.</p>
{% else %}
{% include event.html
	title=event.title
	location=event.location
	start_time=event.beginsOn
	end_time=event.endsOn
	description=event.description
	url=event.url
	thumbnail=event.thumbnailurl
	organizerAvatar=event.organizerAvatar
	organizer=event.organizer
	groupUrl=event.groupUrl
	%}
{% endif %}
{% endmobilizonAgenda %}
```

## How to use it?

Add these lines into your `_config.yml`
```yml
mobilizon_fetch: true # false if you want to deactivate it
mobilizon_url: "https://mobilizon.fr"
mobilizon_cachedir: "mobilizon" # the name of the local folder used to cache the results
mobilizon_timezone: "Europe/Paris" # used to convert the dates
mobilizon_whitelist: # list of the mobilizon groups you want to display on your website
  - my_group
  - my_second_group
```

Add `mobilizon-agenda.rb` into your `_plugins` folder.
