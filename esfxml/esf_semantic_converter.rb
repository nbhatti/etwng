require "sea_grids"
require "poi"
require "commander_details"
require "etw_region_names"

module EsfSemanticConverter
  ConvertSemanticAry = Hash.new{|ht,k| ht[k]={}}
  ConvertSemanticRec = Hash.new{|ht,k| ht[k]={}}

## Utility functions  
  def convert_ary_contents_str(tag)
    data = get_ary_contents(:s).flatten
    raise SemanticFail.new if data.any?{|name| name =~ /\s/}
    out_ary!(tag, "", data.map{|name| " #{name.xml_escape}" })
  end

  def ensure_types(actual, *expected_types)
    (actual_type, actual_data) = *actual
    raise SemanticFail.new unless actual_type == expected_types
    actual_data
  end

  def ensure_loc(loc)
    loc_type, loc_data = loc
    if loc_type == [:s, :s] and loc_data == ["", ""]
      ""
    elsif loc_type == [:s] and loc_data != [""]
      loc_data[0]
    else
      raise SemanticFail.new
    end
  end

  def ensure_date(date)
    year, season = ensure_types(date, :u, :asc)
    raise SemanticFail.new if season =~ /\s/
    if year == 0 and season == "summer"
      nil
    else
      "#{season} #{year}"
    end
  end
  
  def ensure_unit_history(unit_history)
    date, a, b = ensure_types(unit_history, [:rec, :DATE, nil], :u, :u)
    date = ensure_date(date)
    raise SemanticFail.new unless a == 0 and b == 0 and date
    date
  end

## Tag converters

## startpos.esf arrays
  def lookahead_faction_ids
    save_ofs = @ofs
    ofs_end = get_u
    count = get_u
    
    rv = {}
    id = nil
    
    count.times do
      rec_end_ofs = get_u
      return nil unless get_byte == 0x80
      return nil unless get_node_type_and_version[0] == :FACTION # Version number doesn't really matter
      return nil unless rec_end_ofs == get_u
      while @ofs < rec_end_ofs
        t = get_byte
        if t == 0x80 or t == 0x81
          @ofs += 3
          @ofs  = get_u
        elsif t == 4
          id = get_u
        elsif t == 8
          @ofs += 4
        elsif t == 14
          if @abcf
            rv[id] = @str_lookup[get_u]
          else
            rv[id] = get_s
          end
          @ofs = rec_end_ofs
        else
          warn "Unexpected field type #{t} during lookahead of faction ids"
          return nil
        end
      end
    end
    return rv
  ensure
    @ofs = save_ofs
  end

  def convert_ary_FACTION_ARRAY
    @faction_ids = lookahead_faction_ids
    raise QuietSemanticFail.new
  end

  def convert_ary_UNIT__LIST
    data = get_ary_contents(:s).flatten
    raise SemanticFail.new if data.any?{|name| name =~ /\s/}
    out_ary!("unit_list", "", data.map{|name| " #{name.xml_escape}" })
  end

  def convert_ary_CAI_HISTORY_EVENT_HTML_CLASSES
    data = get_ary_contents(:asc).flatten
    raise SemanticFail.new if data.any?{|name| name =~ /\s/}
    out_ary!("cai_event_classes", "", data.map{|name| " #{name.xml_escape}" })
  end

  def convert_ary_UNIT_CLASS_NAMES_LIST
    data = get_ary_contents([:rec, :CAMPAIGN_LOCALISATION, nil], :bool)
    data = data.map{|loc, used|
      loc = ensure_loc(loc)
      raise SemanticFail.new if loc =~ /\s|=/
      [loc, used]
    }
    out_ary!("unit_class_names_list", "", data.map{|loc, used| " #{loc}=#{used ? 'yes' : 'no'}"})
  end
  
  def convert_ary_REGION_OWNERSHIP
    data = get_ary_contents(:s, :s)
    raise SemanticFali.new if data.any?{|region, owner| region =~ /\s|=/ or owner =~ /\s|=/}
    out_ary!("region_ownership", "", data.map{|region,owner| " #{region.xml_escape}=#{owner.xml_escape}" })
  end

  def convert_ary_RELIGION_BREAKDOWN
    data = get_ary_contents(:s, :flt)
    raise SemanticFali.new if data.any?{|name, value| name =~ /\s|=/}
    out_ary!("religion_breakdown", "", data.map{|name,value| " #{name.xml_escape}=#{value}" })
  end

  def convert_ary_RESOURCES_ARRAY
    convert_ary_contents_str("resources_array")
  end

  def convert_ary_REGION_KEYS
    convert_ary_contents_str("REGION_KEYS")
  end

  def convert_ary_COMMODITIES_ORDER
    convert_ary_contents_str("commodities_order")
  end

  def convert_ary_RESOURCES_ORDER
    convert_ary_contents_str("resources_order")
  end
  
  def convert_ary_PORT_INDICES
    data = get_ary_contents(:s, :u)
    raise SemanticFali.new if data.any?{|name, value| name =~ /\s|=/}
    out_ary!("port_indices", "", data.map{|name,value| " #{name.xml_escape}=#{value}" })
  end

  def convert_ary_SETTLEMENT_INDICES
    data = get_ary_contents(:s, :u)
    raise SemanticFali.new if data.any?{|name, value| name =~ /\s|=/}
    out_ary!("settlement_indices", "", data.map{|name,value| " #{name.xml_escape}=#{value}" })
  end
  
  def convert_ary_AgentAttributes
    data = get_ary_contents(:s, :i)
    out_ary!("agent_attributes", "", data.map{|attribute,level| " #{attribute.xml_escape}=#{level}" })
  end
  
  def convert_ary_AgentAttributeBonuses
    data = get_ary_contents(:s, :u)
    out_ary!("agent_attribute_bonuses", "", data.map{|attribute,level| " #{attribute.xml_escape}=#{level}" })
  end
  
  def convert_ary_AgentAncillaries
    convert_ary_contents_str("agent_ancillaries")
  end
  
## regions.esf arrays

  def convert_rec_query_info
    annotate_rec "query_info",
      [:u, 0] => "number of quads",
      [:u, 1] => "number of cells (cell = quad not empty)"
  end

  def convert_rec_cell
    (x,y), id, data = get_rec_contents(:v2, :u, :bin8)
    raise SemanticFali.new if (data.size % 16) != 0
    data = data.unpack("l*")
    
    out!(%Q[<cell x='#{x}' y='#{y}' id='#{id}'>])
    until data.empty?
      coord1, coord2, id1, id2 = data.shift(4)
      out!(%[ <cell_quad id1='#{id1}' coord1='#{coord1}' id2='#{id2}' coord2='#{coord2}'/>])
    end
    out!(%Q[</cell>])
  end
  
  def convert_rec_transition_links
    annotate_rec "transition_links",
      [:u, 1] => "turns needed",
      [:u, 2] => "destination theatre #",
      [:u, 3] => "area # inside destination theatre"
  end

  def convert_rec_slot_descriptions
    v2a_annotations = [
      "land area",
      "sea area (present only for ports)",
      "total area (different from land area only in ports)",
    ]
    each_rec_member("slot_descriptions") do |ofs_end, i|
      next unless @data[@ofs] == 0x4c
      annotation = v2a_annotations.shift
      next unless annotation
      annotation = "<!-- #{annotation} -->"

      data = get_value![1].unpack("f*").map(&:pretty_single)
      if data.empty?
        out!("<v2_ary/>" + annotation)
      else
        out!("<v2_ary>" + annotation)
        out!(" #{data.shift},#{data.shift}") until data.empty?
        out!("</v2_ary>")
      end
    end
  end

  def convert_ary_region_keys
    data = get_ary_contents(:s, :v2)
    raise SemanticFali.new if data.any?{|name, xy| name =~ /\s|=|,/}
    out_ary!("region_keys", "", data.map{|name,(x,y)| " #{name.xml_escape}=#{x},#{y}"})
  end

  def convert_ary_groundtype_index
    convert_ary_contents_str("groundtype_index")
  end

  def convert_ary_land_indices
    data = get_ary_contents(:s, :byte)
    raise SemanticFali.new if data.any?{|name, value| name =~ /\s|=/}
    out_ary!("land_indices", "", data.map{|name,value| " #{name.xml_escape}=#{value}" })
  end

  def convert_ary_sea_indices
    data = get_ary_contents(:s, :byte)
    raise SemanticFali.new if data.any?{|name, value| name =~ /\s|=/}
    out_ary!("sea_indices", "", data.map{|name, value| " #{name.xml_escape}=#{value}" })
  end
  
  def convert_ary_DIPLOMACY_RELATIONSHIP_ATTITUDES_ARRAY
    draa_labels = [
      "State gift received",
      "Military alliance",
      "Alliance Broken",
      "Alliances not honoured",
      "Enemy of my enemy",
      "Trade Agreement",
      "Trade Agreement broken",
      "War",
      "Peace Treaty",
      "Allied with enemy",
      "War declared on friend",
      "Unreliable ally",
      "Territorial expansion",
      "Backstabber",
      "Assassination attempts",
      "Religion",
      "Government type",
      "Historical Friendship/Grievance",
      "Acts of sabotage",
      "Acts of espionage",
      "Threats of Attack",
      "Unknown (does not seem to do anything)",
    ]
    data = get_ary_contents(:i, :i, :i, :bool, :i, :bool)
    out!("<ary type=\"DIPLOMACY_RELATIONSHIP_ATTITUDES_ARRAY\">")
    data.each_with_index do |entry, i|
      label = draa_labels[i] || "Unknown #{i}"
      a,b,c,d,e,f = *entry
      d = d ? 'yes' : 'no'
      f = f ? 'yes' : 'no'
      if [a,b,c,d] == [0, 0, 0, 'no']
        abcd = ""
      else
        abcd = %Q[ drift="#{a}" current="#{b}" limit="#{c}" active1="#{d}"]
      end
      if [e,f] == [0, 'no']
        ef = ""
      else
        ef =  %Q[ extra="#{e}" active2="#{f}"]
      end
      out!(" <draa#{abcd}#{ef}/><!-- #{label.xml_escape} -->")
    end
    out!("</ary>")
  end
  
## traderoutes.esf arrays

  def convert_ary_SETTLEMENTS
    convert_ary_contents_str("settlements")
  end

## pathfinding.esf arrays

  def convert_rec_grid_data
    region_names = nil
    
    each_rec_member("grid_data") do |ofs_end, i|
      if i == 0 and lookahead_v2x?(ofs_end)
        x = get_value![1] * 0.5**20
        y = get_value![1] * 0.5**20
        out!(%Q[<v2x x="#{x}" y="#{y}"/> <!-- starting point -->])
      elsif i == 1 and @data[@ofs] == 0x07
        v = get_value![1]
        out!(%Q[<u2>#{v}</u2> <!-- starting x cell -->])
      elsif i == 2 and @data[@ofs] == 0x07
        v = get_value![1]
        out!(%Q[<u2>#{v}</u2> <!-- starting y cell -->])
      elsif i == 3 and @data[@ofs] == 0x04
        v = get_value![1]
        vs = v * 0.5**20
        out!(%Q[<i>#{v}</i> <!-- dimension of cells (#{vs}) -->])
      elsif i == 4 and @data[@ofs] == 0x08
        v = get_value![1]
        out!(%Q[<u>#{v}</u> <!-- columns -->])
      elsif i == 5 and @data[@ofs] == 0x08
        v = get_value![1]
        out!(%Q[<u>#{v}</u> <!-- rows -->])
      elsif i == 7 and @data[@ofs] == 0x07
        v = get_value![1]
        out!(%Q[<u2>#{v}</u2> <!-- number of passable regions -->])
      elsif i == 8 and @data[@ofs] == 0x07
        v = get_value![1]
        out!(%Q[<u2>#{v}</u2> <!-- number of listed regions (generally equals to the previous number, but not compulsory) -->])
      elsif i == 9 and @data[@ofs] == 0x43
        v = get_value![1].unpack("s*")
        region_names = {}

        out!(%Q[<i2_ary>])
        v.each_with_index{|r, i|
          region_names[i+1] = region_name = EtwRegionNames[r]
          out!(%Q[ #{r} <!-- #{region_name} -->])
        }
        out!(%Q[</i2_ary>])
      elsif i == 10 and @data[@ofs] == 0x47 and region_names
        v = get_value![1].unpack("v*")
            
        out!(%Q[<u2_ary>])

        idx_to_names = []
          
        while v[0] != 0
          i    = v.shift
          name = region_names[i]
          idx_to_names << name
          out!(" #{i} <!-- #{name} -->")
        end

        v.shift
        out!("")
        out!(" 0 <!-- separator -->")
        out!("")

        until v.empty?
          sz = v.shift
          elems = (0...sz).map{ v.shift }
          elems_names = elems.map{|i| idx_to_names[i-1] }
          out!(%Q[ #{sz} #{elems.join(", ")} <!-- #{elems_names.join(", ") }-->])
        end
           
        out!(%Q[</u2_ary>])
      end
    end
  end

  def convert_ary_vertices
    data = get_ary_contents(:i, :i)
    @pathfinding_vertices_ary = data
    scale = 0.5**20
    out_ary!("vertices", "", data.map{|x,y|
      " #{x*scale},#{y*scale}"
    })
  end
  
  def convert_rec_pathfinding_areas
    each_rec_member("pathfinding_areas") do |ofs_end, i|
      next unless i == 1 and @data[@ofs] == 0x48
      data = get_value![1].unpack("V*")
      out!("<u4_ary>")
      cnt = 0
      scale = 0.5**20
      until data.empty?
        i = data.shift
        if cnt == 0
          cnt = i
          out!("")
          out!(" #{i} <!-- vertices count -->")
          nx_has_0123 = !(data[0, i] & [0,1,2,3]).empty?
          if nx_has_0123
            # out!(" <!-- open line -->")
          else
            out!(" <!-- closed line -->")
          end
        else
          x, y = @pathfinding_vertices_ary[i]
          x = x*scale
          y = y*scale
          if i <= 3
            out!(" #{i}")
          else
            out!(" #{i} <!-- #{x},#{y} -->")
          end
          cnt -= 1
        end
      end
      out!("</u4_ary>")
    end
    @pathfinding_vertices_ary = nil
  end
  
## regions.esf records
  def lookahead_region_data_vertices
    return nil unless @data[@ofs+4] == 0x80
    return nil unless @data[@ofs+12] == 0x4c
    end_ofs, = @data[@ofs+13, 4].unpack("V")
    @data[@ofs+17..end_ofs].unpack("f*").map(&:pretty_single)
  end
  
  def convert_rec_region_data
    @region_data_vertices = lookahead_region_data_vertices
    tag!("rec", :type=>"region_data") do
      convert_until_ofs!(get_u)
    end
    @region_data_vertices = nil
  end

  def convert_rec_faces
    raise SemanticFail.new unless @region_data_vertices
    data, = get_rec_contents(:bin8)
    tag!("rec", :type=>"faces") do
      out!("<u4_ary>")
      data.unpack("V*").each do |i|
        x = @region_data_vertices[2*i]
        y = @region_data_vertices[2*i+1]
        out!(" #{i} <!-- #{x} #{y}-->")
      end
      out!("</u4_ary>")
    end
  end
  
  def convert_rec_outlines
    raise SemanticFail.new unless @region_data_vertices
    each_rec_member("outlines") do |ofs_end, i|
      next unless @data[@ofs] == 0x48
      data = get_value![1]
      out!("<u4_ary>")
      data.unpack("V*").each do |i|
        x = @region_data_vertices[2*i]
        y = @region_data_vertices[2*i+1]
        out!(" #{i} <!-- #{x} #{y}-->")
      end
      out!("</u4_ary>")
    end
  end
  
  def convert_rec_BOUNDS_BLOCK
    (xmin, ymin), (xmax, ymax) = get_rec_contents(:v2, :v2)
    out!("<bounds_block xmin=\"#{xmin}\" ymin=\"#{ymin}\" xmax=\"#{xmax}\" ymax=\"#{ymax}\"/>")
  end

  def convert_rec_black_shroud_outlines
    name, data = get_rec_contents(:s, :v2_ary)
    data = data.unpack("f*").map(&:pretty_single)
    out!("<black_shroud_outlines name=\"#{name.xml_escape}\">")
    out!(" #{data.shift},#{data.shift}") until data.empty?
    out!("</black_shroud_outlines>")
  end

  def convert_rec_connectivity
    mask, cfrom, cto = get_rec_contents(:u, :u, :u)
    out!("<connectivity mask=\"#{"%08x" % mask}\" from=\"#{cfrom}\" to=\"#{cto}\"/>")
  end

  def convert_rec_climate_map
    xsz, ysz, data = get_rec_contents(:u, :u, :bin6)
    path, rel_path = dir_builder.alloc_new_path("maps/climate_map-%d", nil, ".pgm")
    File.write_pgm(path, xsz, ysz, data)
    out!("<climate_map pgm=\"#{rel_path}\"/>")
  end

  def convert_rec_wind_map
    xsz, ysz, unknown, data = get_rec_contents(:u, :u, :flt, :bin2)
    path, rel_path = dir_builder.alloc_new_path("maps/wind_map-%d", nil, ".pgm")
    File.write_pgm(path, xsz*2, ysz, data)
    out!("<wind_map unknown=\"#{unknown}\" pgm=\"#{rel_path.xml_escape}\"/>")
  end
  
  def convert_rec_areas
    each_rec_member("areas") do |ofs_end, i|
      case [i, @data[@ofs, 1]]
      when [0, "\x01"]
        tag = get_value![1] ? "<yes/>" : "<no/>"
        out!("#{tag}<!-- is land bridge -->")
      when [1, "\x01"]
        tag = get_value![1] ? "<yes/>" : "<no/>"
        out!("#{tag}<!-- English Channel coast ? -->")
      when [2, "\x01"]
        tag = get_value![1] ? "<yes/>" : "<no/>"
        out!("#{tag}<!-- passable -->")
      when [5, "\x07"]
        v = get_value![1]
        out!("<u2>#{v}</u2><!-- unknown1 id -->")
      when [8, "\x07"]
        v = get_value![1]
        out!("<u2>#{v}</u2><!-- unknown2 id -->")
      when [9, "\x07"]
        v = get_value![1]
        labels = {104 => "mainland"}
        label = labels[v] ? " (#{v}=#{labels[v]})" : ""
        out!("<u2>#{v}</u2><!-- island id#{label} -->")
      end
    end
  end

## startpos.esf records
  def convert_rec_CAMPAIGN_VICTORY_CONDITIONS
    campaign_type_labels = [" (short)", " (long)", " (prestige)", " (global domination)", " (unplayable)"]
    data = get_rec_contents([:ary, :REGION_KEYS, nil], :bool, :u, :u, :bool, :u, :bool, :bool)
    regions, flag1, year, region_count, prestige_victory, campaign_type, flag2, flag3 = *data
    regions = regions.map{|region| ensure_types(region, :s)}.flatten
    campaign_type = "#{campaign_type}#{campaign_type_labels[campaign_type]}"
    prestige_victory = prestige_victory ? 'yes' : 'no'
    raise SemanticFail.new unless [flag1, flag2, flag3] == [false, false, false]
    out_ary!("victory_conditions",
      %Q[ year="#{year}" region_count="#{region_count}" prestige_victory="#{prestige_victory}" campaign_type="#{campaign_type}"],
      regions.map{|name| " #{name.xml_escape}"})
  end
  
  # def convert_rec_BUILDING_CONSTRUCTION_ITEM
  #   pp :bci
  #   types, data = get_rec_contents_dynamic
  #   raise "Die in fire" unless types.shift(5) == [:u, :bool, :u, :u, :u]
  #   code, flag, turns_done, turns, cost = data.shift(5)
  #   pp [:bci, code, flag, "#{turns_done}/#{turns}", cost, types, data] 
  #   puts ""
  #   raise SemanticFail.new
  # end

  
  def convert_rec_CAMPAIGN_BONUS_VALUE_BLOCK
    (types, data), = get_rec_contents([:rec, :CAMPAIGN_BONUS_VALUE, nil])
    # types, data = get_rec_contents_dynamic
    raise "Die in fire" unless types.shift(3) == [:u, :i, :flt]
    type, subtype, value = *data.shift(3)
    case [type, *types]
    when [0, :s]
      out!(%Q[<campaign_bonus_0 subtype="#{subtype}" value="#{value}" agent="#{data[0].xml_escape}"/>])
    when [1]
      out!(%Q[<campaign_bonus_1 subtype="#{subtype}" value="#{value}"/>])
    when [2, :s]
      out!(%Q[<campaign_bonus_2 subtype="#{subtype}" value="#{value}" slot_type="#{data[0].xml_escape}"/>])
    when [3, :s]
      out!(%Q[<campaign_bonus_3 subtype="#{subtype}" value="#{value}" resource="#{data[0].xml_escape}"/>])
    when [6, :s]
      out!(%Q[<campaign_bonus_6 subtype="#{subtype}" value="#{value}" social_class="#{data[0].xml_escape}"/>])
    when [7, :s, :s]
      out!(%Q[<campaign_bonus_7 subtype="#{subtype}" value="#{value}" social_class="#{data[0].xml_escape}" religion="#{data[1].xml_escape}"/>])
    when [8, :s]
      out!(%Q[<campaign_bonus_8 subtype="#{subtype}" value="#{value}" weapon="#{data[0].xml_escape}"/>])
    when [9, :s]
      out!(%Q[<campaign_bonus_9 subtype="#{subtype}" value="#{value}" ammunition="#{data[0].xml_escape}"/>])
    when [10, :s]
      out!(%Q[<campaign_bonus_10 subtype="#{subtype}" value="#{value}" religion="#{data[0].xml_escape}"/>])
    when [11, :s]
      out!(%Q[<campaign_bonus_11 subtype="#{subtype}" value="#{value}" resource="#{data[0].xml_escape}"/>])
    when [12, :s]
      out!(%Q[<campaign_bonus_12 subtype="#{subtype}" value="#{value}" unit_ability="#{data[0].xml_escape}"/>])
    when [14, :s]
      out!(%Q[<campaign_bonus_14 subtype="#{subtype}" value="#{value}" unit_type="#{data[0].xml_escape}"/>])
    else
      pp [:cbv, type, subtype, value, types, data]
      puts ""
      raise SemanticFail.new
    end
  end
  
  def convert_rec_POPULATION__CLASSES
    data, = get_rec_contents([:rec, :POPULATION_CLASS, nil])
    data = ensure_types(data, :s, :bin4, :bin4, :i,:i,:i,:i,:i, :u,:u,:u, :i,:i)
    cls = data.shift
    a1 = data.shift.unpack("l*")
    a2 = data.shift.unpack("l*")
    raise SemanticFail.new unless a1.size == 11
    raise SemanticFail.new unless a2.size == 6
    attrs = [
      ["social_class", cls.xml_escape],

      ["gov_type_happy", a1.shift],
      ["taxes", a1.shift],
      ["religion", a1.shift],
      ["events", a1.shift],
      ["culture", a1.shift],
      ["industry", a1.shift],
      ["characters_happy", a1.shift],
      ["war", a1.shift],
      ["reform", a1.shift],
      ["bankrupcy", a1.shift],
      ["resistance", a1.shift],
      
      ["gov_type", a2.shift],
      ["gov_buildings", a2.shift],
      ["characters", a2.shift],
      ["policing", a2.shift],
      ["garrison", a2.shift],
      ["crackdown", a2.shift],
    
      ["happy_total", data.shift],
      ["unhappy_total", data.shift],
      ["repression_total", data.shift],
      
      ["unknown_1", data.shift],    # rioting-related
      ["turns_rioting", data.shift],
      ["unknown_3", data.shift],    # (uint) rioting related
      ["unknown_4", data.shift],    # (uint) rioting-related
      ["unknown_5", data.shift],    # (uint) 7 is normal, 1/2/6/10 also seen, rioting-related
      ["unknown_zero", data.shift],
      ["foreign", data.shift],
    ]
    raise SemanticFail.new unless a1 == [] and a2 == [] and data == []
    out!("<population_class")
    attrs.each{|name,value|
      out!(%Q[  #{name}="#{value}"])
    }
    out!("/>")
  end
  
  def convert_rec_CAI_BORDER_PATROL_ANALYSIS_AREA_SPECIFIC_PATROL_POINTS
    data, = get_rec_contents([:rec, :CAI_BORDER_PATROL_POINT, nil])
    x, y, a = ensure_types(data, :i, :i, :bin8)
    x *= 0.5**20
    y *= 0.5**20
    a = a.unpack("V*").join(" ")
    out!(%Q[<cai_border_patrol_point x="#{x}" y="#{y}" a="#{a}"/>])
  end
  
  def convert_rec_QUAD_TREE_BIT_ARRAY_NODE
    ofs_end = get_u
    if ofs_end - @ofs == 10 and @data[@ofs] == 0x08 and @data[@ofs+5] == 0x08
      a, b = get_bytes(10).unpack("xVxV")
      a = "%08x" % a
      b = "%08x" % b
      out!(%Q[<quad_tree_leaf>#{a}#{b}</quad_tree_leaf>])
    else
      tag!("quad_tree_node") do
        send(@esf_type_handlers[get_byte]) while @ofs < ofs_end
      end
    end
  end
  
  def lookahead_v2x?(ofs_end)
    @ofs+10 <= ofs_end and @data[@ofs, 1] == "\x04" and @data[@ofs+5, 1] == "\x04"
  end
  
  # Call only if lookahead_v2x? says it's ok
  def convert_v2x!
    x = get_value![1] * 0.5**20
    y = get_value![1] * 0.5**20
    out!(%Q[<v2x x="#{x}" y="#{y}"/>])
  end
  
  def each_rec_member(type)
    tag!("rec", :type => type) do
      ofs_end = get_u
      i = 0
      while @ofs < ofs_end
        xofs = @ofs
        yield(ofs_end, i)
        send(@esf_type_handlers[get_byte]) if xofs == @ofs
        i += 1
      end
    end
  end

  def convert_rec_OBSTACLE
    autoconvert_v2x "OBSTACLE", 7, 8
  end

  def convert_rec_OBSTACLE_BOUNDARIES
    data, = get_rec_contents(:bin8)
    data = data.unpack("V*")
    recs = []
    until data.empty?
      n = data.shift
      raise "Malformatted OBSTACLE_BOUNDARIES" if data.size < 2*n + 2
      recs << [(0...n).map{ [data.shift, data.shift] }, data.shift]
      raise "Malformatted OBSTACLE_BOUNDARIES"  unless data.shift == 0
    end

    out!("<obstacle_boundaries>")
    recs.each do |pairs, id|
      out!(" <obstacle_boundaries_entry id=\"#{id}\">")
      pairs.each do |a,b|
        out!("  #{a} #{b}")
      end
      out!( " </obstacle_boundaries_entry>")
    end
    out!("</obstacle_boundaries>")
  end

  def convert_rec_PATHFINDING_GRID
    each_rec_member("PATHFINDING_GRID") do |ofs_end, i|
      if i == 0 and @data[ofs] == 0x08
        v = get_value![1]
        out!("<u>#{v}</u><!-- number of cells -->")
      elsif i == 1 and @data[ofs] == 0x48
        v = get_value![1].unpack("l*")
        parts = []
        until v.empty?
          sz = v.shift
          parts << {
            :points => (0...sz).map{ [v.shift, v.shift] },
            :type => v.shift,
          }
        end
        out!("<grid_paths>")
        scale = 0.5 ** 20
        parts.each{|part|
          out!(" <grid_path type=\"#{part[:type]}\">")
          part[:points].each{|x,y|
            x *= scale
            y *= scale
            out!("  #{x},#{y}")
          }
          out!(" </grid_path>")
        }
        out!("</grid_paths>")
      elsif i == 5 and @data[ofs] == 0x48
        v = get_value![1].unpack("V*")
        out!("<u4_ary>")
        until v.empty?
          out!(" #{v.shift} #{v.shift}")
        end
        out!("</u4_ary>")
      end
    end
  end

  def convert_rec_LOCOMOTABLE
    each_rec_member("LOCOMOTABLE") do |ofs_end, i|
      # Steps 0/1 take two elements, so steps 6/7 really mean elements 8/9
      if i == 0 or i == 1
        convert_v2x!
      elsif i == 6 and @data[ofs] == 4
        v = get_value![1]
        out!("<i>#{v}</i><!-- Movement Points total -->")
      elsif i == 7 and @data[ofs] == 4
        v = get_value![1]
        out!("<i>#{v}</i><!-- Movement Points left -->")
      end
    end
  end

  def convert_rec_grid_cells
    each_rec_member("grid_cells") do |ofs_end, i|
      if i == 0 and @data[@ofs] == 0x46
        v = get_value![1].unpack("C*")
        str = []
        until v.empty?
          str << v.shift(4).map{|x| "%02x" % x}.join(" ")
        end
        out!("<bin6>#{str.join(' ; ')}</bin6>")
      elsif i == 4 and @data[@ofs] == 0x46
        v = get_value![1].unpack("C*")
        out!("<bin6> <!-- #{v.size/12} empty cells -->")
        until v.empty?
          line = v.shift(12).map{|x| "%02x" % x}
          part0 = line[0,4].join(" ")
          part1 = line[4,4].join(" ")
          part2 = line[8,4].join(" ")
          out!(" #{part0} ; #{part1} ; #{part2}")
        end
        out!("</bin6>")
      end
    end
  end
  
  def convert_rec_FORT
    tag!("rec", :type => "FORT") do
      ofs_end = get_u
      convert_v2x! if lookahead_v2x?(ofs_end)
      send(@esf_type_handlers[get_byte]) while @ofs < ofs_end
    end
  end
  
  def convert_rec_SIEGEABLE_GARRISON_RESIDENCE
    autoconvert_v2x "SIEGEABLE_GARRISON_RESIDENCE", 10
  end
  
  def convert_rec_CAI_BDI_COMPONENT_PROPERTY_SET
    autoconvert_v2x "CAI_BDI_COMPONENT_PROPERTY_SET", 10, 13
  end
  
  def convert_rec_CAI_BDIM_WAIT_HERE
    autoconvert_v2x "CAI_BDIM_WAIT_HERE", 0
  end
  
  def convert_rec_CAI_BDIM_MOVE_TO_POSITION
    autoconvert_v2x "CAI_BDIM_MOVE_TO_POSITION", 1, 5
  end
  
  def convert_rec_CAI_BDI_RECRUITMENT_NEW_FORCE_OF_OR_REINFORCE_TO_STRENGTH
    autoconvert_v2x "CAI_BDI_RECRUITMENT_NEW_FORCE_OF_OR_REINFORCE_TO_STRENGTH", 4
  end
  
  def convert_rec_FACTION
    @dir_builder.faction_name = lookahead_str
    tag!("rec", :type=>"FACTION") do
      convert_until_ofs!(get_u)
    end
    @dir_builder.faction_name = nil
  end

  def covert_v39_rec_FACTION
    @dir_builder.faction_name = lookahead_str
    tag!("rec", :type=>"FACTION", :version => 39) do
      convert_until_ofs!(get_u)
    end
    @dir_builder.faction_name = nil
  end
  
  def convert_rec_FACTION_TECHNOLOGY_MANAGER
    annotate_rec "FACTION_TECHNOLOGY_MANAGER",
      [:i, 1] => "tech tree id"
  end
  
  def convert_rec_REBEL_SETUP
    unit_list, faction, religion, gov, unknown, social_class = get_rec_contents([:ary, :"UNIT LIST", nil], :s, :s, :s, :u, :s)
    attrs = %Q[ faction="#{faction.xml_escape}" religion="#{religion.xml_escape}" gov="#{gov.xml_escape}" unknown="#{unknown}" social_class="#{social_class.xml_escape}"]
    unit_list = unit_list.map{|unit| ensure_types(unit, :s)}.flatten
    out_ary!("rebel_setup", attrs, unit_list.map{|unit| " #{unit}"})
  end
  
  def annotate_rec(type, annotations)
    symbolic_names = [nil, :bool, nil, :i2, :i, nil, :byte, :u2, :u, nil, :flt, nil, :v2, :v3, :s, :asc]
    symbolic_names[0x4c] = :v2_ary
    
    each_rec_member(type) do |ofs_end, i|
      field_type = symbolic_names[@data[ofs]]
      next unless field_type
      annotation = annotations[[field_type, i]]
      next unless annotation
      annotation = "<!-- #{annotation} -->"
      case field_type
      when :s, :asc
        v = get_value![1]
        if v.empty?
          out!("<#{field_type}/>" + annotation)
        else
          out!("<#{field_type}>#{v.xml_escape}</#{field_type}>" + annotation)
        end
      when :i, :u, :u2, :i2, :byte, :flt
        v = get_value![1]
        out!("<#{field_type}>#{v}</#{field_type}>" + annotation)
      when :bool
        tag = get_value![1] ? "<yes/>" : "<no/>"
        out!(tag + annotation)
      when :v2_ary
        data = get_value![1].unpack("f*").map(&:pretty_single)
        if data.empty?
          out!("<v2_ary/>" + annotation)
        else
          out!("<v2_ary>" + annotation)
          out!(" #{data.shift},#{data.shift}") until data.empty?
          out!("</v2_ary>")
        end
      when :v2, :v3
        raise "Implement me: annotations for v2/v3"
      end
    end
  end
  
  def autoconvert_v2x(type, *positions)
    each_rec_member(type) do |ofs_end, i|
      convert_v2x! if positions.include?(i) and lookahead_v2x?(ofs_end)
    end
  end
  
  def convert_rec_REGION
    annotate_rec("REGION",
      [:s, 0] => "name",
      [:i, 4] => "region id"
    )
  end
  
  def convert_rec_REGION_SLOT
    annotate_rec("REGION_SLOT",
      [:u, 2] => "region slot id [?]",
      [:s, 3] => "slot name",
      [:u, 12] => "4294967295 == 0xFFFF_FFFF [?]"
    )
  end
  
  def convert_rec_GOVERNMENT
    annotate_rec "GOVERNMENT",
      [:i, 0] => "government id"
  end
  
  def convert_rec_CHARACTER_POST
    annotate_rec "CHARACTER_POST",
      [:i, 0] => "character id A [???]",
      [:s, 1] => "seat",
      [:u, 2] => "character id B [???]",
      [:i, 4] => "government id",
      [:i, 5] => "government id"
  end
  
  def convert_rec_MILITARY_FORCE
    annotate_rec("MILITARY_FORCE", 
      [:u, 0] => "general character id [?]",
      [:u, 1] => "commander id"
    )
  end

  def convert_rec_ARMY
    annotate_rec("ARMY", 
      [:i, 4] => "general character id [?]"
    )
  end

  def convert_rec_CAI_UNIT
    annotate_rec("CAI_UNIT", 
      [:u, 1] => "unit id"
    )
  end
  
  def convert_rec_CAI_REGION
    annotate_rec("CAI_REGION",
      [:u, 2] => "cai region id",
      [:s, 10] => "name",
      [:u, 11] => "region id",
      [:u, 12] => "cai faction-related-something id [wild guess ???]"
    )
  end
  
  def convert_rec_CAI_REGION_SLOT
    annotate_rec("CAI_REGION_SLOT",
      [:u, 1] => "cai region slot id [???]"
    )
  end
  
  def convert_rec_CAI_SETTLEMENT
    annotate_rec("CAI_SETTLEMENT",
      [:u, 2] => "settlement id [?]"
    )
  end

  def convert_rec_SIEGEABLE_GARRISON_RESIDENCE
    annotate_rec("SIEGEABLE_GARRISON_RESIDENCE",
      [:u, 1] => "slot id [?]"
    )
  end
  
  def convert_rec_CAI_BUILDING_SLOT
    annotate_rec("CAI_BUILDING_SLOT",
      [:u, 0] => "slot id [?]"
    )
  end
  
  def convert_rec_CAI_FACTION
    annotate_rec("CAI_FACTION",
      [:u, 5] => "cai faction id [???]",
      [:u, 6] => "faction id"
    )
  end
  
  def convert_rec_CAI_GOVERNORSHIP
    annotate_rec("CAI_GOVERNORSHIP",
      [:u, 0] => "goverorship id [???]",
      [:u, 1] => "governorship theatre id [???]",
      [:u, 2] => "governorship cai id [???]"
    )
  end
  
  def convert_rec_ORDINAL_PAIR
    name, number = get_rec_contents([:rec, :CAMPAIGN_LOCALISATION, nil], :i)
    name = ensure_loc(name)
    out!(%Q[<ordinal_pair name="#{name.xml_escape}" number="#{number}"/>])
  end
  
  def convert_rec_PORTRAIT_DETAILS
    card, template, info, number = get_rec_contents(:s, :s, :s, :i)
    if [card, template, info, number] == ["", "", "", -1]
      out!(%Q[<portrait_details/>])
    elsif template.empty?
      out!(%Q[<portrait_details card="#{card.xml_escape}" info="#{info.xml_escape}" number="#{number}"/>])
    else
      out!(%Q[<portrait_details card="#{card.xml_escape}" template="#{template.xml_escape}" info="#{info.xml_escape}" number="#{number}"/>])
    end
  end
  
  def convert_rec_GOVERNORSHIP_TAXES
    level_lower, level_upper, rate_lower, rate_upper = get_rec_contents(:u, :u, :byte, :byte)
    out!(%Q[<gov_taxes level_lower="#{level_lower}" level_upper="#{level_upper}" rate_lower="#{rate_lower}" rate_upper="#{rate_upper}"/>])
  end

  def convert_ary_GOV_IMP
    data = get_ary_contents_dynamic
    raise SemanticFail.new unless data.size == 1
    type, data = *data[0]
    case type
    when [[:rec, :"GOVERNMENT::CONSTITUTIONAL_MONARCHY", nil]]
      raise SemanticFail.new unless data.size == 1
      type, data = *data[0]
      raise SemanticFail.new unless type == [:u, :bool, :i]
      minister_changes, had_elections, elections_due = *data
      out!(%Q[<gov_constitutional_monarchy minister_changes="#{minister_changes}" had_elections="#{had_elections ? 'yes' : 'no'}" elections_due="#{elections_due}"/>])
    when [[:rec, :"GOVERNMENT::ABSOLUTE_MONARCHY", nil]]
      raise SemanticFail.new unless data == [[[], []]]
      out!("<gov_absolute_monarchy/>")
    when [[:rec, :"GOVERNMENT::REPUBLIC", nil]]
      raise SemanticFail.new unless data.size == 1
      type, data = *data[0]
      raise SemanticFail.new unless type == [:u, :bool, :i, :u]
      minister_changes, had_elections, elections_due, term = *data
      out!(%Q[<gov_republic minister_changes="#{minister_changes}" had_elections="#{had_elections ? 'yes' : 'no'}" elections_due="#{elections_due}" term="#{term}"/>])
    else
      raise SemanticFail.new
    end
  end
  
  # This is somewhat dubious
  # Type seems to be:
  # * u, false, v2x
  # * u, true u, v2x
  # Revert if it causes any problems
  def convert_rec_CAI_TRADE_ROUTE_POI_RAID_ANALYSIS
    autoconvert_v2x "CAI_TRADE_ROUTE_POI_RAID_ANALYSIS", 2, 3
  end
  
  def convert_rec_CAI_BDIM_SIEGE_SH
    autoconvert_v2x "CAI_BDIM_SIEGE_SH", 5
  end
  
  def convert_rec_REGION_SLOT
    autoconvert_v2x "REGION_SLOT", 6
  end
  
  def convert_rec_CAI_HLPP_INFO
    autoconvert_v2x "CAI_HLPP_INFO", 1
  end
  
  def convert_rec_CAI_BORDER_PATROL_ANALYSIS_AREA_SPECIFIC
    autoconvert_v2x "CAI_BORDER_PATROL_ANALYSIS_AREA_SPECIFIC", 3
  end
  
  def convert_rec_CAI_BDI_UNIT_RECRUITMENT_NEW
    autoconvert_v2x "CAI_BDI_UNIT_RECRUITMENT_NEW", 0
  end
  
  def convert_rec_FAMOUS_BATTLE_INFO
    x, y, name, a, b, c, d = get_rec_contents(:i, :i, :s, :i, :i, :i, :bool)
    x *= 0.5**20
    y *= 0.5**20
    d = d ? "yes" : "no"
    out!(%Q[<famous_battle_info x="#{x}" y="#{y}" name="#{name}" a="#{a}" b="#{b}" c="#{c}" d="#{d}"/>])
  end

  def convert_rec_CAI_REGION_HLCI
    a, b, c, x, y = get_rec_contents(:u, :u, :bin8, :i, :i)
    x *= 0.5**20
    y *= 0.5**20
    c = c.unpack("V*").join(" ")
    out!(%Q[<cai_region_hlci a="#{a}" b="#{b}" c="#{c}" x="#{x}" y="#{y}"/>])
  end

  def convert_rec_CAI_TRADING_POST
    a, x, y, b = get_rec_contents(:u, :i, :i, :u)
    x *= 0.5**20
    y *= 0.5**20
    out!(%Q[<cai_trading_post cai_theatres_id="#{a}" x="#{x}" y="#{y}" b="#{b}"/>])
  end

  def convert_rec_CAI_SITUATED
    x, y, a, b, c = get_rec_contents(:i, :i, :u, :bin8, :u)
    x *= 0.5**20
    y *= 0.5**20
    b = b.unpack("V*").join(" ")
    out!(%Q[<cai_situated x="#{x}" y="#{y}" a="#{a}" b="#{b}" c="#{c}"/>])
  end
    
  def convert_rec_THEATRE_TRANSITION_INFO
    link, a, b, c = get_rec_contents([:rec, :CAMPAIGN_MAP_TRANSITION_LINK, nil], :bool, :bool, :u)
    fl, time, dest, via = ensure_types(link, :flt, :u, :u, :u)
    raise SemanticFail.new if fl != 0.0 or b != false or c != 0
    if [a, time, dest, via] == [false, 0, 0xFFFF_FFFF, 0xFFFF_FFFF]
      out!("<theatre_transition/>")
    elsif a == true and time > 0 and dest != 0xFFFF_FFFF and via != 0xFFFF_FFFF
      out!(%Q[<theatre_transition turns="#{time}" destination="#{dest}" via="#{via}"/>])
    else
      raise SemanticFail.new
    end
  end

  def convert_rec_CAI_TECHNOLOGY_TREE
    data, = get_rec_contents(:u)
    out!("<cai_technology_tree>#{data}</cai_technology_tree><!-- tech tree id -->")
  end
  
  def convert_rec_RandSeed
    data, = get_rec_contents(:u)
    out!("<rand_seed>#{data}</rand_seed>")
  end

  def convert_rec_LAND_UNIT
    unit_type, unit_data, zero = get_rec_contents([:rec, :LAND_RECORD_KEY, nil], [:rec, :UNIT, nil], :u)
    unit_type, = ensure_types(unit_type, :s)
    raise SemanticError.new unless zero == 0
    
    unit_data = ensure_types(unit_data,
      [:rec, :UNIT_RECORD_KEY, nil],
      [:rec, :UNIT_HISTORY, nil],    
      [:rec, :COMMANDER_DETAILS, nil],
      [:rec, :TRAITS, nil],
      :i,
      :u,
      :u,
      :i,
      :u,
      :u,
      :u,
      :u,
      :u,
      :byte,
      [:rec, :CAMPAIGN_LOCALISATION, nil]
    )
    raise SemanticError.new unless unit_type == ensure_types(unit_data.shift, :s)[0]
    unit_history = ensure_unit_history(unit_data.shift)
    
    fnam, lnam, faction = ensure_types(unit_data.shift, [:rec, :CAMPAIGN_LOCALISATION, nil], [:rec, :CAMPAIGN_LOCALISATION, nil], :s)
    commander = CommanderDetails.parse(ensure_loc(fnam), ensure_loc(lnam), faction)
    raise SemanticFail.new unless commander
    
    traits, = ensure_types(unit_data.shift, [:ary, :TRAIT, nil])
    raise SemanticFail.new unless traits == []
    
    unit_id = unit_data.shift
    current_size = unit_data.shift
    max_size = unit_data.shift
    mp = unit_data.shift
    kills  = unit_data.shift
    deaths = unit_data.shift
    commander_id = unit_data.shift
    commander_id = nil if commander_id == 0
    
    raise SemanticFail.new unless unit_data.shift == kills
    raise SemanticFail.new unless unit_data.shift == deaths
    
    exp = unit_data.shift
    name = ensure_loc(unit_data.shift)
    
    raise SemanticFail.new unless unit_data == []

    tag!("land_unit",
      :unit_id => unit_id,
      :commander_id => commander_id,
      :size => "#{current_size}/#{max_size}",
      :name => name,
      :commander => commander,
      :exp => exp,
      :kills => kills,
      :deaths => deaths,
      :mp => mp,
      :created => unit_history,
      :type => unit_type
    )
  end
  
  def convert_rec_GARRISON_RESIDENCE
    data, = get_rec_contents(:u)
    out!("<garrison_residence>#{data}</garrison_residence>")
  end
  
  def convert_rec_OWNED_INDIRECT
    data, = get_rec_contents(:u)
    out!("<owned_indirect>#{data}</owned_indirect>")
  end
  
  def convert_rec_OWNED_DIRECT
    data, = get_rec_contents(:u)
    out!("<owned_direct>#{data}</owned_direct>")
  end
  
  def convert_rec_FACTION_FLAG_AND_COLOURS
    path, r1,g1,b1, r2,g2,b2, r3,g3,b3 = get_rec_contents(:s, :byte,:byte,:byte, :byte,:byte,:byte, :byte,:byte,:byte)
    color1 = "#%02x%02x%02x" % [r1,g1,b1]
    color2 = "#%02x%02x%02x" % [r2,g2,b2]
    color3 = "#%02x%02x%02x" % [r3,g3,b3]
    out!("<flag_and_colours path=\"#{path.xml_escape}\" color1=\"#{color1.xml_escape}\" color2=\"#{color2.xml_escape}\" color3=\"#{color3.xml_escape}\"/>")
  end
  
  def convert_rec_techs
    status_hint = {0 => " (done)", 2 => " (researchable)", 4 => " (not researchable)"}
    data = get_rec_contents(:s, :u, :flt, :u, :bin8, :u)
    name, status, research_points, school_slot_id, unknown1, unknown2 = *data
    status = "#{status}#{status_hint[status]}"
    unknown1 = unknown1.unpack("V*").join(" ")
    out!("<techs name=\"#{name.xml_escape}\" status=\"#{status}\" research_points=\"#{research_points}\" school_slot_id=\"#{school_slot_id}\" unknown1=\"#{unknown1}\" unknown2=\"#{unknown2}\"/>")
  end

  def convert_rec_COMMANDER_DETAILS
    fnam, lnam, faction = get_rec_contents([:rec, :CAMPAIGN_LOCALISATION, nil], [:rec, :CAMPAIGN_LOCALISATION, nil], :s)
    fnam = ensure_loc(fnam)
    lnam = ensure_loc(lnam)
    commander = CommanderDetails.parse(fnam, lnam, faction)
    if commander
      out!("<commander>#{commander.xml_escape}</commander>")
    else
      out!("<commander_details name=\"#{fnam.xml_escape}\" surname=\"#{lnam.xml_escape}\" faction=\"#{faction.xml_escape}\"/>")
    end
  end

  def convert_rec_AgentAbilities
    ability, level, attribute = get_rec_contents(:s, :i, :s)
    out!("<agent_ability ability=\"#{ability.xml_escape}\" level=\"#{level}\" attribute=\"#{attribute.xml_escape}\"/>")
  end
  
  def convert_rec_BUILDING
    health, name, faction, gov = get_rec_contents(:u, :s, :s, :s)
    out!("<building health=\"#{health}\" name=\"#{name.xml_escape}\" faction=\"#{faction.xml_escape}\" government=\"#{gov.xml_escape}\"/>")
  end
  
  def convert_rec_DATE
    date = ensure_date(get_rec_contents_dynamic)
    if date
      out!("<date>#{date.xml_escape}</date>")
    else
      out!("<date/>")
    end
  end
    
  def convert_rec_UNIT_HISTORY
    date = ensure_unit_history(get_rec_contents_dynamic)
    out!("<unit_history>#{date.xml_escape}</unit_history>")
  end
  
  def convert_rec_MAPS
    name, x, y, unknown, data = get_rec_contents(:s, :u, :u, :i, :bin8)
    raise SemanticFail.new if name =~ /\s/
    path, rel_path = dir_builder.alloc_new_path("map-%d", nil, ".pgm")
    File.write_pgm(path, x*4, y, data)
    out!("<map name=\"#{name.xml_escape}\" unknown=\"#{unknown}\" pgm=\"#{rel_path.xml_escape}\"/>")
  end

  def convert_rec_CAMPAIGN_LOCALISATION
    loc_type, loc_data = get_rec_contents_dynamic
    if loc_type == [:s] and loc_data != [""]
      out!("<loc>#{loc_data[0].xml_escape}</loc>")
    elsif loc_type == [:s, :s] and loc_data == ["", ""]
      out!("<loc/>")
    elsif loc_type == [:s, :s] and loc_data[0] == "" and loc_data[1] != ""
      loc_data[1]
      out!("<loc2>#{loc_data[1].xml_escape}</loc2>")
    else
      raise SemanticFail.new
    end
  end

  def convert_rec_LAND_RECORD_KEY
    key, = get_rec_contents(:s)
    out!("<land_key>#{key.xml_escape}</land_key>")
  end

  def convert_rec_UNIT_RECORD_KEY
    key, = get_rec_contents(:s)
    out!("<unit_key>#{key.xml_escape}</unit_key>")
  end

  def convert_rec_NAVAL_RECORD_KEY
    key, = get_rec_contents(:s)
    out!("<naval_key>#{key.xml_escape}</naval_key>")
  end

  def convert_rec_TRAITS
    traits, = get_rec_contents([:ary, :TRAIT, nil])
    traits = traits.map{|trait| ensure_types(trait, :s, :i)}
    raise SemanticFail.new if traits.any?{|trait, level| trait =~ /\s|=/}
    out_ary!("traits", "", traits.map{|trait, level| " #{trait.xml_escape}=#{level}" })
  end

  def convert_rec_ANCILLARY_UNIQUENESS_MONITOR
    entries, = get_rec_contents([:ary, :ENTRIES, nil])
    entries = entries.map{|entry| ensure_types(entry, :s)}.flatten
    raise SemanticFail.new if entries.any?{|entry| entry =~ /\s|=/}
    out_ary!("ancillary_uniqueness_monitor", "", entries.map{|entry| " #{entry.xml_escape}" })
  end
  
  def convert_rec_REGION_OWNERSHIPS_BY_THEATRE
    theatre, ownerships = get_rec_contents(:s, [:ary, :REGION_OWNERSHIPS, nil])
    ownerships = ownerships.map{|o| ensure_types(o, :s, :s)}
    raise SemanticFail.new if ownerships.any?{|region, owner| region =~ /\s|=/ or owner =~ /\s|=/}
    out_ary!("region_ownerships_by_theatre", " theatre=\"#{theatre.xml_escape}\"", ownerships.map{|region, owner| " #{region.xml_escape}=#{owner.xml_escape}" })
  end
  
  def convert_rec_ALLIED_IN_WAR_AGAINST
    each_rec_member("ALLIED_IN_WAR_AGAINST") do |ofs_end, i|
      if i == 0 and @data[@ofs] == 0x08
        id = get_value![1]
        tag = "<u>#{id}</u>"        
        tag += "<!-- #{@faction_ids[id].xml_escape} -->" if @faction_ids and @faction_ids[id]
        out!(tag)
      end
    end
  end
  
  def convert_rec_DIPLOMACY_RELATIONSHIP
    each_rec_member("DIPLOMACY_RELATIONSHIP") do |ofs_end, i|
      case [i, @data[@ofs]]
      when [0, 0x04]
        id = get_value![1]
        tag = "<i>#{id}</i>"        
        tag += "<!-- #{@faction_ids[id].xml_escape} -->" if @faction_ids and @faction_ids[id]
        out!(tag)
      when [2, 0x01]
        tag = get_value![1] ? "<yes/>" : "<no/>"
        out!("#{tag}<!-- trade agreement -->")
      when [3, 0x04]
        val = get_value![1]
        out!("<i>#{val}</i><!-- military access turns (-1 = unlimited) -->")
      when [4, 0x0e]
        val = get_value![1]
        out!("<s>#{val.xml_escape}</s><!-- relationship -->")
      when [20, 0x0e]
        val = get_value![1]
        out!("<s>#{val.xml_escape}</s><!-- this is NOT relationship -->")
      end
    end
  end

## bmd.dat records

  def convert_rec_HEIGHT_FIELD
    xi, yi, (xf, yf), data, unknown, hmin, hmax = get_rec_contents(:u, :u, :v2, :flt_ary, :i, :flt, :flt)
    path, rel_path = dir_builder.alloc_new_path("height_field-%d", nil, ".pgm")
    File.write_pgm(path, 4*xi, yi, data)
    out!("<height_field xsz=\"#{xf}\" ysz=\"#{yf}\" pgm=\"#{rel_path.xml_escape}\" unknown=\"#{unknown}\" hmin=\"#{hmin}\" hmax=\"#{hmax}\"/>")
  end
  
  def convert_rec_GROUND_TYPE_FIELD
    xi, yi, (xf, yf), data = get_rec_contents(:u, :u, :v2, :bin4)
    path, rel_path = dir_builder.alloc_new_path("group_type_field", nil, ".pgm")
    File.write_pgm(path, 4*xi, yi, data)
    out!("<ground_type_field xsz=\"#{xf}\" ysz=\"#{yf}\" pgm=\"#{rel_path.xml_escape}\"/>")
  end
  
  def convert_rec_BMD_TEXTURES
    types, data = get_rec_contents_dynamic
    tag!("bmd_textures") do
      until data.empty?
        if data.size == 3 and types == [:u, :u, :bin6]
          xsz, ysz, pxdata = data
          path, rel_path = dir_builder.alloc_new_path("bmd_textures/texture-%d", nil, ".pgm")
          File.write_pgm(path, 4*xsz, ysz, pxdata)
          out!("<bmd_pgm pgm=\"#{rel_path.xml_escape}\"/>")
          break
        end
        t = types.shift
        v = data.shift
        
        case t
        when :s
          out!("<s>#{v.xml_escape}</s>")
        when :i
          out!("<i>#{v}</i>")
        when :u
          out!("<u>#{v}</u>")
        when :bool
          if v
            out!("<yes/>")
          else
            out!("<no/>")
          end
        when :bin6
          rel_path = dir_builder.save_binfile("bmd_textures/texture", nil, ".jpg", v)
          out!("<bin6ext path=\"#{rel_path.xml_escape}\"/>")
        else
          # Should be possible to recover from it, isn't just yet
          raise "Total failure while converting BMD_TEXTURES"
        end
      end
    end
  end

## poi.esf
  def convert_rec_CAI_POI_ROOT
    pois = PoiEsfParser.new(*get_rec_contents_dynamic).get_pois
    
    tag!("pois") do
      pois.each do |poi|
        code1 = poi.shift
        flag1 = poi.shift
        x, y = poi.shift
        region_name, region_id = poi.shift
        val1 = poi.shift
        ary1 = poi.shift
        val2 = poi.shift
        ary2 = poi.shift
        ary3 = poi.shift
        code2 = poi.shift
        flag2 = poi.shift
        raise SemanticFail.new unless poi == []
        attrs = {
          :x => x, :y => y,
          :region_name => region_name,
          :region_id => region_id,
          :code1 => code1,
          :code2 => code2,
          :flag1 => flag1 ? 'yes' : 'no',
          :flag2 => flag2 ? 'yes' : 'no',
          :val1 => val1,
          :val2 => val2,
          :ids => ary3.join(" ")
        }
        if ary1.empty? and ary2.empty?
          tag!("poi", attrs)
        else
          tag!("poi", attrs) do
            ary1.each{|name, val|
              out!(%Q[<poi_region1 name="#{name}" val="#{val}"/>])
            }
            ary2.each{|name, val|
              out!(%Q[<poi_region2 name="#{name}" val="#{val}"/>])
            }
          end
        end
      end
    end
  end
  
## sea_grids.esf
  def convert_rec_CAI_SEA_GRID_ROOT
    sea_grids = SeaGridsEsfParser.new(*get_rec_contents_dynamic).get_sea_grids
    
    tag!("sea_grids") do
      sea_grids.each do |grid_name, (min_x, min_y), (max_x, max_y), factor, areas, connections|
        tag!("theatre_sea_grid",
            :name => grid_name,
            :minx => min_x, :miny => min_y, :maxx => max_x, :maxy => max_y,
            :factor => factor
          ) do
          areas.each do |row|
            tag!("sea_grid_row") do
              row.each do |(cmin_x, cmin_y), (cmax_x, cmax_y), area_id, lands, seas, ports, numbers|
                tag!("sea_grid_cell", :area_id => area_id, :minx => cmin_x, :miny => cmin_y, :maxx => cmax_x, :maxy => cmax_y) do
                  out_ary!("sea_grid_lands", "", lands.map{|x| " #{x}"})
                  out_ary!("sea_grid_seas", "", seas.map{|x| " #{x}"})
                  out_ary!("sea_grid_ports", "", ports.map{|x| " #{x}"})
                  out_ary!("sea_grid_numbers", "", numbers.empty? ? "" : " " + numbers.join(" "))
                end
              end
            end
          end
          tag!("sea_grid_connections") do
            connections.each do |area1, area2, x|
              out!("<sea_grid_connection area1=\"#{area1}\" area2=\"#{area2}\" value=\"#{x}\"/>")
            end
          end
        end
      end
    end
  end

## farm_tile_templates
  def convert_rec_WALL_POST_LIST
    data, = get_rec_contents([:rec, :WALL_POST, nil])
    (x, y), (dx, dy) = ensure_types(data, :v2, :v2)
    out!(%Q[<wall_post x="#{x}" y="#{y}" dx="#{dx}" dy="#{dy}"/>])
  end
  
  def convert_rec_FARM_TREE_LIST
    data, = get_rec_contents([:rec, :FARM_TREE, nil])
    type, (x, y) = ensure_types(data, :s, :v2)
    out!(%Q[<farm_tree type="#{type.xml_escape}" x="#{x}" y="#{y}"/>])
  end
  
  def convert_rec_ID_LIST
    data, = get_rec_contents(:bin8)
    data = data.unpack("V*")
    if data.empty?
      out!("<id_list/>")
    else
      out!("<id_list>#{data.join(" ")}</id_list>")
    end
  end
  
## autoconfigure everything

  self.instance_methods.each do |m|
    if m.to_s =~ /\Aconvert_ary_(.*)\z/
      ConvertSemanticAry[nil][$1.gsub("__", " ").to_sym] = m
    elsif m.to_s =~ /\Aconvert_rec_(.*)\z/
      ConvertSemanticRec[nil][$1.gsub("__", " ").to_sym] = m
    end
  end
  ConvertSemanticRec[39][:FACTION] = :covert_v39_rec_FACTION
end
