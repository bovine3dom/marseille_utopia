# Marseille Saint-Charles inter-platform walking times

Calculate walking times from the voie F segment `[3182917809, 10852831327]` approach to the underpass.
Both endpoints and every point on this segment have zero travel time.

- `extract.jl`: fetches OSM data and calculates walking times.
- `docs/index.html`: static map.
- `docs/network.geojson`: generated WGS84 sections and times.
- `data/saint_charles.json` and `data/station.json`: cached OSM data.

To update the map data:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. extract.jl
```

Walking speed is 1.3 m/s, with an extra 10 seconds per mapped stairway.

## Walking with luggage

- [Huang et al. (2019), section 3.1](https://scholars.cityu.edu.hk/ws/portalfiles/portal/34818366/17.pdf)
  measured about 1.2 m/s for individual walkers with trolley cases in a 0.5 m aisle.
  Small bags gave about 1.5 m/s. Trolley cases weighed up to 10 kg.
- [Shah et al. (2013), table 2](https://easts.info/on-line/proceedings/vol9/PDF/P269.pdf)
  measured a mean horizontal speed of 0.386 m/s on station stairs for passengers with substantial hand luggage.
  The survey covered 1,118 passengers at Vadodara station around a train arrival.
- [Giannoulaki and Christoforou (2024), section 3.5](https://doi.org/10.3390/su16114813)
  report mixed luggage effects across studies. Bag size and travel purpose are possible explanations.

(i then couldn't be bothered to integrate this and just picked 1.3 m/s)

## Data

The script fetches mapped paths within 800 m of `43.304017, 5.382463`.
It keeps complete ways, including their OSM tags and ordered node IDs.
Edit the query in `extract.jl` to change the extract.
Delete a cached JSON file to fetch current data or apply a changed query.
Set `OVERPASS_URL` to use another Overpass endpoint, for example:

```sh
OVERPASS_URL=https://maps.mail.ru/osm/tools/overpass/api/interpreter julia --project=. extract.jl
```

Data: © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), ODbL.
