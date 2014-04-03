# The SessionService is the single source for insession
# data and contains the session logic.
#
sessionFunc = ($log, privatePub, util, $rootScope, $timeout, upstream,
               config, blackbox) ->

  # reconfigure blackbox
  blackbox.setStreamingServer config.streaming_server

  # initialize defaults
  discussion = config.discussion
  users = config.session
  config.flags =
    onair: false
    reqmic: false
    acceptOrDecline: false
    settings: false

  # some utility functions for the statemachine's callbacks
  subscribeAllStreams = ->
    $log.debug 'subscribing to all streams...'
    for id, user of users
      if user.state in ['OnAir', 'HostOnAir']
        unless id is "#{config.user_id}"
          $log.debug "subscribe to #{user.name}"
          blackbox.subscribe user.stream

  unsubscribeAllStreams = ->
    # TODO blackbox.unsubscribeAll()

  reportState = (state) ->
    # $log.info "reporting new state: #{state}"
    upstream.state state

  # definition of the state machine, incl. callbacks
  # https://github.com/jakesgordon/javascript-state-machine/blob/master/README.md
  fsm = StateMachine.create
    initial: config.initial_state
    events: config.statemachine
    callbacks:
      onenterstate: (event, from, to) ->
        switch to
          when 'Registering', 'GuestRegistering', 'HostRegistering'
            # FIXME the timeout is a hack! better: wait until subscribed
            $timeout (-> reportState(to)), 2000
          else
            reportState(to)
      onleaveWaiting: ->
        subscribeAllStreams()
      onleaveHostRegistering: ->
        subscribeAllStreams()
        config.flags.settings = true
      onleaveGuestRegistering: ->
        subscribeAllStreams()
        config.flags.settings = true
      onListening: ->
        unless config.user.role == 'listener'
          config.flags.reqmic = true 
      onleaveListening: ->
        config.flags.reqmic = false
        true
      onbeforeMicRequested: ->
        config.flags.settings = true
      onAcceptingPromotion: ->
        config.flags.acceptOrDecline = true
      onleaveAcceptingPromotion: ->
        config.flags.acceptOrDecline = false
        true
      onbeforePromotionAccepted: ->
        config.flags.settings = true
      onOnAir: ->
        blackbox.publish config.stream
        config.flags.onair = true
      onleaveOnAir: ->
        blackbox.unpublish()
        config.flags.onair = false
        true
      onHostOnAir: ->
        users = config.session
        blackbox.publish config.stream
        config.flags.onair = true
        # start the talk immediately or with timeout
        # negative numbers will timeout immediately
        # TODO check for brwoser compatibility
        if config.talk.state == 'prelive'
          $log.debug "schedule startTalk for in " +
            util.toHHMMSS(config.talk.starts_in)
          millisecs = config.talk.starts_in * 1000
          # skip timeout if longer than 24.8 days
          # see http://stackoverflow.com/questions/3468607
          return if millisecs > 2147483647
          $timeout startTalk, millisecs
      onleaveHostOnAir: ->
        blackbox.unpublish()
        config.flags.onair = false
        true
      onLoitering: ->
        config.flags.settings = false
        unsubscribeAllStreams()

  # comprehending queries on the state
  isNotRegisteringNorWaiting = ->
    !fsm.current.match /(Register|Wait)ing$/

  # the pushMsgHandler is single point of entry for push notifications
  #
  # For now all messages are publicly communicated, so the pushMsgHandler
  # has to check whether the event is addressed to the current user
  # and thus has to be handled differently.
  #
  # unpack, guard, delegate and trigger refresh
  pushMsgHandler = (data) ->
    data = data.data # unpack private_pub message
    if data.message
      # enrich discussion with further data for display
      user = users[data.message.user_id]
      data.message.name = user.name
      data.message.image = user.image
      # prepend to discussion array
      discussion.unshift data.message
    if method = data.state || data.event
      if data.user?.id == config.user_id
        egoMsgHandler method, data
      else
        stateHandler method, data if data.state
        eventHandler method, data if data.event
    $rootScope.$apply()

  # the egoMsgHandlers will trigger transitions and other side
  # effects based on incoming state notifications as well as
  # events. It will only handle messages targeted at it's own user.
  egoMsgHandler = (method, data) ->
    $log.debug "ego: #{method}"
    switch method
      when 'Registering', 'GuestRegistering', 'HostRegistering'
        fsm.Registered()
        users[data.user.id] = data.user
      when 'Waiting' # state
        if config.talk.state == 'live'
          # TODO pull session info
          fsm.TalkStarted()
      when 'Promote' # event
        fsm.Promoted()
      when 'Demote' # event
        fsm.Demoted()
    # store the current state on the users hash
    users[data.user.id].state = fsm.current

  # the stateHandler handles the state notification of other users
  stateHandler = (state, data) ->
    $log.debug "user #{data.user.id}: #{state}"
    users[data.user.id]?.state = state
    switch state
      when 'Registering', 'GuestRegistering', 'HostRegistering'
        users[data.user.id] = data.user
      when 'OnAir', 'HostOnAir'
        if isNotRegisteringNorWaiting()
          blackbox.subscribe users[data.user.id].stream
      # TODO instead of this react on event Demote
      when 'Listening'
        if isNotRegisteringNorWaiting()
          # TODO blackbox.unsubscribe users[data.user.id].stream
          ;

  # the eventHandler handles events (as opposed to states)
  eventHandler = (event, data) ->
    $log.debug "event: #{event}"
    switch event
      when 'StartTalk'
        config.talk.state = 'live'
        unless fsm.is('HostOnAir')
          users = data.session # TODO check if needed
          fsm.TalkStarted()
      when 'EndTalk'
        config.talk.state = 'postlive'
        fsm.TalkEnded()
      when 'Process'
        config.talk.state = 'processing'
      when 'Archive'
        config.talk.state = 'archived'
        $log.debug data.links
        config.talk.links = data.links

  # some methods only available to the host
  promote = (id) ->
    upstream.event 'Promote', user: { id }
  demote = (id) ->
    return fsm.Demoted() if id is config.user_id
    upstream.event 'Demote', user: { id }
  startTalk = ->
    $log.debug "--- starting Talk ---"
    upstream.event 'StartTalk'
  endTalk = ->
    upstream.event 'EndTalk'

  # separate the audience into four groups
  guests = ->
    (user for id, user of users when user.state == 'OnAir')
  expectingPromotion = ->
    (user for id, user of users when user.state == 'ExpectingPromotion')
  acceptingPromotion = ->
    (user for id, user of users when user.state == 'AcceptingPromotion')
  participants = ->
    (user for id, user of users when user.role == 'participant' and
      user.state == 'Listening')
  listeners = ->
    (user for id, user of users when user.role == 'listener')

  # TODO idealy this should move into callback: on/Registering$/
  # subscribe to push notifications
  privatePub.subscribe "/#{config.namespace}/public", pushMsgHandler
  # privatePub.subscribe "/#{config.namespace}/private/#{name}", dataHandler

  # exposed objects
  { 
    # -- events
    promote
    demote
    endTalk
    # --- groups
    guests
    expectingPromotion
    acceptingPromotion
    participants
    listeners
    # -- misc
    discussion
    upstream
    name: config.fullname
    fsm
    # -- debug
    users
  }

# annotate with dependencies to inject
sessionFunc.$inject = ['$log', 'privatePub', 'util', '$rootScope',
                       '$timeout', 'upstream', 'config', 'blackbox']
Livepage.factory 'session', sessionFunc
