# Encoding: utf-8
# -----------------------------------------------------------------------------
# Project : Dragons Gifts
# -----------------------------------------------------------------------------
# Author :
# -----------------------------------------------------------------------------
# License : GNU Lesser General Public License
# -----------------------------------------------------------------------------
# Creation : 16-Jan-2014
# Last mod : 28-Jan-2014
# -----------------------------------------------------------------------------

MODE_INTRO          = 0
MODE_TOUR           = 1
MODE_START_OVERVIEW = 2
MODE_OVERVIEW       = 3

# -----------------------------------------------------------------------------
#
#    NAVIGATION
#
# -----------------------------------------------------------------------------
class Navigation

  CONFIG =
    urls :
      geojson  : "static/data/africa.json"
      tour     : "static/data/tour.json"
      overview : "static/data/global_view.json"

  constructor: ->
    @projects        = undefined
    @mode            = undefined
    @current_project = undefined

    @uis =
      page              : $(".container:first")
      switch_mode_radio : $(".toggle-radio input[name=ab]")

    # bind event
    @uis.switch_mode_radio.change(@onSwitchRadioChanged)

  start: =>
    queue()
      .defer(d3.json, CONFIG.urls.geojson)
      .defer(d3.json, CONFIG.urls.tour)
      .defer(d3.json, CONFIG.urls.overview)
      .await(@loadedDataCallback)

  loadedDataCallback: (error, geojson, tour, overview) =>
    @setMode(MODE_INTRO)
    @projects    = tour
    @overview    = overview
    geo_features = topojson.feature(geojson, geojson.objects.continent_Africa_subunits).features
    @map         = new AfricaMap(this, geo_features, @projects, @overview)
    @panel       = new Panel(this)

  setMode: (mode) =>
    if @mode != mode
      @mode = mode
      # set a project if the tour mode is selected
      if @mode == MODE_TOUR
        if @current_project?
          @setProject(@current_project)
        else
          @setProject(0)
      else
        @setProject(null)
      # update the mode switcher radio
      if @mode == MODE_TOUR
        @uis.switch_mode_radio.prop('checked', false).filter("[value=tour]").prop('checked', true)
      else if @mode == MODE_OVERVIEW
        @uis.switch_mode_radio.prop('checked', false).filter("[value=overview]").prop('checked', true)
      # trigger an event for the others widgets
      $(document).trigger("modeChanged", @mode)

  setProject: (project) =>
    """
    use this function to set a project.
    it will trigger an projectSelected event that all the other widget
    are able to bind.
    """
    # we need an interger as @current_project
    if project? and typeof(project) is "object"
      project = @projects.indexOf(project)
    if project != @current_project
      # save the state of the selected project
      @current_project = project
      # ensure the mode
      @setMode(MODE_TOUR) unless not project?
      # trigger a projectSelected with the selected project or null if no project is selected
      $(document).trigger("projectSelected", if @current_project? then @projects[@current_project] else null)

  nextProject: =>
    if @hasNext()
      @setProject(@projects[@current_project + 1])
    else # if it's after the last project, we switch to the START_OVERVIEW mode
      @setMode(MODE_START_OVERVIEW)

  previousProject: =>
    if @hasPrevious()
      @setProject(@projects[@current_project - 1])
    else # if it's before the first project, we switch to the INTRO mode
      @setMode(MODE_INTRO)

  hasNext    : => @current_project < @projects.length - 1
  hasPrevious: => @current_project > 0

  onSwitchRadioChanged: =>
    if @uis.switch_mode_radio.filter(":checked").val() == "overview"
      @setMode(MODE_OVERVIEW)
    else
      @setMode(MODE_INTRO)

# -----------------------------------------------------------------------------
#
#    PANEL
#
# -----------------------------------------------------------------------------
class Panel

  constructor: (navigation) ->

    @navigation = navigation

    @uis =
      views          : $(".Panel .view")
      intro          : $(".Panel .view.intro_main")
      single_project : $(".Panel .view.single_project")
      start_overview : $(".Panel .view.start_overview")
      overview       : $(".Panel .view.overview")
      navigation_btn : $(".Panel .navigation-buttons")
      prv_button     : $(".Panel .prv_button")
      nxt_button     : $(".Panel .nxt_button")
      tour_button    : $(".Panel .tour_button")
      overview_button: $(".Panel .overview_button")
      title          : $(".Panel .single_project .title")
      location       : $(".Panel .single_project .location")
      description    : $(".Panel .single_project .description")

    # Bind events
    $(window).resize(@relayout)
    $(document).on("projectSelected", @onProjectSelected)
    $(document).on("modeChanged"    , @onModeChanged)
    @uis.prv_button     .on 'click',    @navigation.previousProject
    @uis.nxt_button     .on 'click',    @navigation.nextProject
    @uis.tour_button    .on 'click', => @navigation.setMode(MODE_TOUR)
    @uis.overview_button.on 'click', => @navigation.setMode(MODE_OVERVIEW)

    # resize
    @relayout()

  relayout: =>
    # usefull for the scrollbar:
    # set the description height to use the overflow: auto style
    description    = $($(".Panel .description").get(@navigation.mode)) # select the current description
    navigation_btn = $(@uis.navigation_btn.get(@navigation.mode))
    description.css
      height : $(window).height() - description.offset().top - navigation_btn.outerHeight(true)

  onProjectSelected: (e, project) =>
    if project?
      @uis.title       .html project.title
      @uis.location    .html project.recipient_condensed
      @uis.description .html project.description

  onModeChanged: (e, mode) =>
    @uis.intro         .toggleClass("hidden", mode != MODE_INTRO)
    @uis.single_project.toggleClass("hidden", mode != MODE_TOUR)
    @uis.start_overview.toggleClass("hidden", mode != MODE_START_OVERVIEW)
    @uis.overview      .toggleClass("hidden", mode != MODE_OVERVIEW)
    @relayout() # resize because the view has changed

# -----------------------------------------------------------------------------
#
#    AFRICA MAP
#
# -----------------------------------------------------------------------------
class AfricaMap

  CONFIG =
    svg_height          : 500
    svg_width           : 500
    initial_zoom        : 350
    close_zoom          : 800
    initial_center      : [15, 0]
    scale_range_tour    : [6, 9]  # scale for compute the circle radius
    scale_range_overview: [4, 15] # scale for compute the circle radius
    transition_map_duration    : 1500
    transition_circle_duration : 500
    transition_circle_ease     : "easeOutExpo"

  constructor: (navigation, countries, projects, overview) ->
    @navigation = navigation
    @countries  = countries
    @projects   = projects
    @overview   = overview

    # Create svg tag
    @svg = d3.select(".africa-container")
      .insert("svg", ":first-child")
      .attr("width", CONFIG.svg_width)
      .attr("height", CONFIG.svg_height)

    # Create projection
    @projection = d3.geo.mercator()
      .center(CONFIG.initial_center)
      .scale(CONFIG.initial_zoom)
      .translate([CONFIG.svg_width/2, CONFIG.svg_height/2])

    # Create the Africa path
    @path = d3.geo.path()
      .projection(@projection)

    @group = @svg.append("g")
    # Create the group of path and add graticule
    @groupPaths = @group.append("g")
      .attr("class", "all-path")

    @groupOverview = @group.append("g")
      .attr("class", "all-overview-points")

    @groupProject = @group.append("g")
      .attr("class", "all-project-points")

    @drawAfricaMap()
    @initProjectCircles()

    # Bind events
    $(document).on("modeChanged"    , @onModeChanged)
    $(document).on("projectSelected", @onProjectSelected)

  drawAfricaMap: =>
    # Create every countries
    @groupPaths.selectAll("path")
      .data(@countries)
      .enter()
        .append("path")
        .attr("d", @path)

  drawCircles: (scale, radius_field_name="usd_defl", appearing_animatation=true) =>
    that = this
    @circles.each (d) ->
      d3.select(this)
        .attr("cx", (d) -> that.projection([d.lon, d.lat])[0])
        .attr("cy", (d) -> that.projection([d.lon, d.lat])[1])
      if appearing_animatation
        d3.select(this)
          .attr("r" , 0) # init rayon before transition
          .transition()
            .ease(CONFIG.transition_circle_ease)
            .duration(CONFIG.transition_circle_duration)
            .delay(CONFIG.transition_map_duration)
              .attr("r" , (d) -> scale(parseFloat(d[radius_field_name])))
      else
       d3.select(this)
        .attr("r" , (d) -> scale(parseFloat(d[radius_field_name])))

  initProjectCircles: =>
    that = this
    # compute scale
    values = @projects.map((d) -> parseFloat(d.usd_defl))
    @project_scale  = d3.scale.linear()
      .domain([Math.min.apply(Math, values), Math.max.apply(Math, values)])
      .range(CONFIG.scale_range_tour)
    #remove previous circles
    @groupOverview.selectAll("circle").transition()
      .ease(CONFIG.transition_circle_ease)
      .duration(CONFIG.transition_circle_duration)
      .attr("r", 0).remove()
    # create circles
    @circles = @groupProject.selectAll("circle")
      .data(@projects)
    @circles.enter()
      .append("circle")
        .on 'click', (d) ->
          that.navigation.setProject(d)
          $(this).trigger("mouseout") # hide the tooltip
    # postioning cirlces
    @drawCircles(@project_scale)
    # tooltip
    @circles.each (d) ->
      $(d3.select(this)).qtip
        content: "#{d.title}<br/>#{d.recipient_oecd_name}"
        show: 'mouseover'
        hide:
          when:
            event: 'mouseout'
        style:
          padding: 5
          tip: 'bottomLeft'
        position:
          adjust:
            x : that.project_scale(d.usd_defl) * 1.75
          corner:
            target : 'topRight'
            tooltip: 'bottomLeft'

  onProjectSelected: (e, project) =>
    # select a cirlce
    @circles.each (d, i) ->
      d3.select(this).classed("active", project is d)
    # zoom
    selected = @circles.filter((d) -> d is project)
    if project? # zoom
      center = [project.lon, project.lat]
      @projection.center(center).scale(CONFIG.close_zoom)
      @groupPaths.selectAll("path")
        .transition().duration(CONFIG.transition_map_duration)
        .attr("d", @path)
      @drawCircles(@project_scale, "usd_defl")
    else # dezoom
      @projection.center(CONFIG.initial_center).scale(CONFIG.initial_zoom)
      @groupPaths.selectAll("path")
        .transition().duration(CONFIG.transition_map_duration)
        .attr("d", @path)
      @drawCircles(@project_scale)

  initOverviewCircles: =>
    that = this
    # compute scale
    values = @overview.map((d) -> parseFloat(d.USD))
    scale  = d3.scale.linear()
      .domain([Math.min.apply(Math, values), Math.max.apply(Math, values)])
      .range(CONFIG.scale_range_overview)

    #remove previous circles
    @groupProject.selectAll("circle").transition()
      .ease(CONFIG.transition_circle_ease)
      .duration(CONFIG.transition_circle_duration)
      .attr("r", 0).remove()
    @circles = @groupOverview.selectAll("circle")
      .data(@overview)
    @circles.enter()
      .append("circle")
    @drawCircles(scale, "USD")

  onModeChanged: (e, mode) =>
    if mode == MODE_OVERVIEW
      @initOverviewCircles()
    else
      @initProjectCircles()

# -----------------------------------------------------------------------------
#
#    MAIN
#
# -----------------------------------------------------------------------------
navigation = new Navigation()
navigation.start()

# EOF
