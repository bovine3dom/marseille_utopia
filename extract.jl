using Downloads, JSON3

origin = (3182917809, 10852831327)
walking_speed = 1.3 # metres per second
stair_penalty = 10.0 # seconds per mapped stairway
section_length = 3.0 # maximum metres per coloured section
# Passage, eight approach paths, and eight stairways.
underpass_ways = Set([312432482, 312432422, 312432423, 312432428, 312432429,
    312432430, 312432433, 312432441, 312432444, 1183878016, 1183878017,
    1183878018, 1183878019, 1183878020, 1183878021, 1183878022, 1183878023])

query = """
[out:json][timeout:60];
way["highway"~"^(footway|path|pedestrian|steps|corridor)\$"]["area"!="yes"]
  (around:800,43.304017,5.382463);
out geom;
"""

data_dir = joinpath(@__DIR__, "data")
mkpath(data_dir)

function fetch_osm(query, filename)
    path = joinpath(data_dir, filename)
    raw = if isfile(path)
        read(path, String)
    else
        response = IOBuffer()
        result = Downloads.request(get(ENV, "OVERPASS_URL", "https://overpass-api.de/api/interpreter");
            method="POST", input=IOBuffer(query), output=response, timeout=90)
        result.status == 200 || error("Overpass HTTP $(result.status)")
        String(take!(response))
    end
    osm = JSON3.read(raw)
    haskey(osm, :remark) && error(osm.remark)
    isempty(osm.elements) && error("Overpass returned an empty extract")
    isfile(path) || write(path, raw)
    osm
end
osm = fetch_osm(query, "saint_charles.json")
station = only(fetch_osm("[out:json];way(1166213063);out geom;", "station.json").elements)

ring = [[p.lon, p.lat] for p in station.geometry]
function inside_station(p)
    isodd(count(zip(ring[1:end-1], ring[2:end])) do (a, b)
        (a[2] > p[2]) != (b[2] > p[2]) &&
            p[1] < (b[1] - a[1]) * (p[2] - a[2]) / (b[2] - a[2]) + a[1]
    end)
end
function metres(a, b)
    lat1, lat2 = deg2rad(a[2]), deg2rad(b[2])
    h = sin((lat2 - lat1) / 2)^2 + cos(lat1) * cos(lat2) * sin(deg2rad(b[1] - a[1]) / 2)^2
    2 * 6371008.8 * asin(sqrt(clamp(h, 0, 1)))
end
coords = Dict(n => [p.lon, p.lat] for w in osm.elements for (n, p) in zip(w.nodes, w.geometry))
edges = []
for way in osm.elements
    underpass = way.id in underpass_ways
    (underpass || (get(way.tags, :level, "0") == "0" && get(way.tags, :tunnel, "no") != "yes")) || continue
    get(way.tags, :foot, get(way.tags, :access, "yes")) in ("no", "private") && continue
    for i in 1:length(way.nodes)-1
        a, b = way.nodes[i:i+1]
        inside_station((coords[a] + coords[b]) / 2) || continue
        length_m = metres(coords[a], coords[b])
        source = (a, b) == origin || (b, a) == origin
        seconds = source ? 0.0 : length_m / walking_speed +
            (way.tags.highway == "steps" ? stair_penalty / (length(way.nodes) - 1) : 0)
        push!(edges, (; a, b, length_m, seconds, source, underpass))
    end
end
any(e -> e.source, edges) || error("The origin segment is missing from the station network")

function travel_times(edges, underpass_open)
    adj = Dict(n => Tuple{Int,Float64}[] for e in edges for n in (e.a, e.b))
    for e in edges
        e.underpass && !underpass_open && continue
        push!(adj[e.a], (e.b, e.seconds))
        push!(adj[e.b], (e.a, e.seconds))
    end
    times = Dict(n => (n in origin ? 0.0 : Inf) for n in keys(adj))
    todo = Set(keys(adj))
    while !isempty(todo)
        u = argmin(n -> times[n], todo)
        isfinite(times[u]) || break
        delete!(todo, u)
        for (v, seconds) in adj[u]
            times[v] = min(times[v], times[u] + seconds)
        end
    end
    times
end
closed_times = travel_times(edges, false)
open_times = travel_times(edges, true)

arrival(t, e, x) = min(t[e.a] + x * e.seconds, t[e.b] + (1 - x) * e.seconds)
# Maximum arrival time over a section, including an interior peak.
worst(t, e, lo, hi) = min(t[e.a] + hi * e.seconds, t[e.b] + (1 - lo) * e.seconds,
    (t[e.a] + t[e.b] + e.seconds) / 2)
finite(t, rounding=ceil) = isfinite(t) ? rounding(Int, t) : nothing
features = []
for e in edges
    pieces = max(1, ceil(Int, e.length_m / section_length))
    for j in 0:pieces-1
        lo, hi = j / pieces, (j + 1) / pieces
        closed = e.underpass ? Inf : worst(closed_times, e, lo, hi)
        opened = worst(open_times, e, lo, hi)
        saved = isfinite(closed) && isfinite(opened) ?
            max(0, minimum(arrival(closed_times, e, x) - arrival(open_times, e, x) for x in (lo, hi))) : Inf
        properties = (closed_s=finite(closed), open_s=finite(opened),
            saved_s=finite(saved, floor), underpass=e.underpass)
        points = [round.((1 - x) * coords[e.a] + x * coords[e.b]; digits=7) for x in (lo, hi)]
        push!(features, (type="Feature", properties=properties,
            geometry=(type="LineString", coordinates=points)))
    end
end
path = joinpath(@__DIR__, "www", "network.geojson")
mkpath(dirname(path))
write(path, JSON3.write((type="FeatureCollection", features=features,
    origin=[coords[n] for n in origin], attribution=osm.osm3s.copyright)))
println("$(length(features)) sections → $path")
