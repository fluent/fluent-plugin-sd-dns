# DNS based service discovery plugin for [Fluentd](https://fluentd.org)

The `dns` service discovery plugin updates target services by DNS list.

This plugin uses `Socket.getaddrinfo` internally.

## Requirements

- Fluentd v1.8 or later

## Installation

Use RubyGems:

    fluent-gem install fluent-plugin-sd-dns --no-document

## Configuration

Use `@type dns` in `<service_discovery>`.

```
<match pattern>
  @type forward

  <service_discovery>
    @type dns
    <entry>
      host host1.domain
      port 24224
    </entry>
    <entry>
      host host2.domain
      port 24225
    </entry>
  </service_discovery>
</match>
```

If `host1.domain` returns 3 addresses and `host2.domain` returns 2 addresses, `sd_dns` generates 5 address entries with given port.

e.g.

- `host1.domain` returns `1.2.3.4`, `1.2.3.5` and `1.2.3.6`
- `host2.domain` returns `2.2.3.4` and `2.2.3.5`

`sd_dns` generates `1.2.3.4:24224`, `1.2.3.5:24224`, `1.2.3.6:24224`, `2.2.3.4:24225` and `2.2.3.5:24225`.

### <entry> section

Specify host and additional information. Each entry has the following parameters:

- host
- port
- address_family
- shared_key
- username
- password
- weight

#### host

- Type: string

Hostname for service lookup. This is *required* parameter

#### port

- Type: integer

Port of service. This is *required* parameter

#### address_family

- Type: string (`ipv4` or `ipv6`)
- Default: nil (both)

Specify the desired address family. By default, `sd_dns` gets IPv4 and IPv6 addresses. If you want to get only IPv4 or IPv6, set it.

```
<entry>
  host host1.domain
  port 24224
  address_family ipv4
</entry>
```

#### shared_key

- Type: string
- Default: nil

The shared_key per entry

#### username

- Type: string
- Default: empty string

The username for authentication.

#### password

- Type: string
- Default: empty string

The password for authentication

#### weight

- Type: Integer
- Default: 60

The load balancing weight

`shared_key`, `username`, `password` and `weight` are mainly for `out_forward`.

```
<match pattern>
  @type forward

  <service_discovery>
    @type dns
    <entry>
      host host1.domain
      port 24224
      username user1
      password pass1
      shared_key key1
      weight 80
    </entry>
    <entry>
      host host2.domain
      port 24225
      username user2
      password pass2
      shared_key key2
      weight 20
    </entry>
  </service_discovery>
</match>
```

### interval

- Type: time
- Default: nil (no update)

Interval for updating the service list. By default, `sd_dns` keeps to use first service list. If you want to update the service list periodically, set `interval` parameter.

```
<match pattern>
  @type forward

  <service_discovery>
    @type dns
    interval 60s
    <entry>
      host host.domain
      port 80
    </entry>
  </service_discovery>
</match>
```

### ignore_dns_error

- Type: bool
- Default: false

Ignore DNS related error or not. This parameter is for multiple `<entry>` case. By default, `sd_dns` will stop the update process when raises an error in DNS resolution.

If you want to contine the update process, set `ignore_dns_error true`

```
<match pattern>
  @type forward

  <service_discovery>
    @type dns
    interval 60
    ignore_dns_error true
    <entry>
      host host1.domain  # 
      port 24224
    </entry>
    <entry>
      host host2.domain
      port 24225
    </entry>
  </service_discovery>
</match>
```

When error happens, `sd_dns` generates following warning message:

```
failed to get service list from host1.domain
```

## More information

- Copyright: 2020- Fluentd Authors
- License: Apache License, Version 2.0
