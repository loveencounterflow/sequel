
'use strict'



############################################################################################################
CND                       = require 'cnd'
rpr                       = CND.rpr
badge                     = 'DESQL'
debug                     = CND.get_logger 'debug',     badge
warn                      = CND.get_logger 'warn',      badge
info                      = CND.get_logger 'info',      badge
urge                      = CND.get_logger 'urge',      badge
help                      = CND.get_logger 'help',      badge
whisper                   = CND.get_logger 'whisper',   badge
echo                      = CND.echo.bind CND
#...........................................................................................................
types                     = new ( require 'intertype' ).Intertype
{ isa
  equals
  type_of
  validate
  validate_list_of }      = types.export()
GUY                       = require 'guy'
{ DBay }                  = require 'dbay'
{ SQL }                   = DBay
to_snake_case             = require 'just-snake-case'
{ antlr: ANTLR          } = require 'rhombic'


#===========================================================================================================
#
#-----------------------------------------------------------------------------------------------------------
class @Desql

  #---------------------------------------------------------------------------------------------------------
  constructor: ( P... ) ->
    throw new Error "^345^ configuration settings not supported" if P.length > 0
    @db = new DBay()
    @_procure_infrastructure()
    @_compile_sql()
    return undefined

  #---------------------------------------------------------------------------------------------------------
  _procure_infrastructure: ->
    ### TAINT check if tables exist ###
    @db.create_stdlib()
    #.......................................................................................................
    @db SQL"""
      create table queries (
          qid     integer not null primary key,
          length  integer generated always as ( length( query ) ),
          query   text    not null );"""
    #.......................................................................................................
    @db SQL"""
      create table raw_nodes (
          qid     integer not null,
          id      integer not null,
          xtra    integer not null default 1,
          upid    integer,
          type    text    not null,
          pos1    integer,
          pos2    integer,
          lnr1    integer,
          col1    integer,
          lnr2    integer,
          col2    integer,
        primary key ( qid, id, xtra ),
        foreign key ( qid ) references queries
        -- foreign key ( upid ) references raw_nodes ( id ) DEFERRABLE INITIALLY DEFERRED
        );"""
    #.......................................................................................................
    @db SQL"""
      create view _coverage_1 as select
          n.qid                                                 as qid,
          n.id                                                  as id,
          n.xtra                                                as xtra,
          n.type                                                as type,
          n.pos1                                                as pos1,
          n.pos2                                                as pos2,
          substring( q.query, n.pos1, n.pos2 - n.pos1 + 1 )     as txt
        from raw_nodes as n
        join queries as q using ( qid )
        where pos1 is not null;"""
    #.......................................................................................................
    @db SQL"""
      create view _coverage_holes_1 as select
          qid                                                   as qid,
          id                                                    as id,
          xtra                                                  as prv_xtra,
          type                                                  as prv_type,
          pos1                                                  as pos1,
          pos2                                                  as pos2,
          txt                                                   as txt,
          pos2 + 1                                              as nxt_pos1,
          lead( pos1 ) over w - 1                               as nxt_pos2
        from _coverage_1 as c
        window w as ( partition by qid order by pos1 );"""
    #.......................................................................................................
    @db SQL"""
      create view _coverage_holes_2 as select
          c.qid                                                           as qid,
          c.id                                                            as id,
          c.prv_xtra                                                      as prv_xtra,
          c.prv_type                                                      as prv_type,
          c.nxt_pos1                                                      as pos1,
          c.nxt_pos2                                                      as pos2,
          substring( q.query, c.nxt_pos1, c.nxt_pos2 - c.nxt_pos1 + 1 )   as txt
        from _coverage_holes_1  as c
        join queries            as q using ( qid )
        where c.nxt_pos1 <= c.nxt_pos2
      ;"""
    #.......................................................................................................
    @db SQL"""
      create view _coverage_holes as select
          c.qid                                                           as qid,
          c.id                                                            as id,
          2                                                               as xtra,
          case when std_str_is_blank( c.txt ) then 'ws'
            else 'missing' end                                            as type,
          c.pos1                                                          as pos1,
          c.pos2                                                          as pos2,
          c.txt                                                           as txt
        from _coverage_holes_2  as c
      ;"""
    #.......................................................................................................
    @db SQL"""
      create view coverage as select
          *
        from _coverage_1
        where txt != ''
      union all select
          *
        from _coverage_holes
        order by qid, pos1;"""
    #.......................................................................................................
    return null

  #---------------------------------------------------------------------------------------------------------
  _compile_sql: ->
    GUY.props.hide @, 'statements',
      #.....................................................................................................
      insert_query: @db.prepare_insert
        into:         'queries'
        exclude:      [ 'qid', ]
        returning:    '*'
      #.....................................................................................................
      insert_special_node: @db.prepare_insert
        into:         'raw_nodes'
        returning:    '*'
      #.....................................................................................................
      insert_regular_node: @db.prepare SQL"""
        insert into raw_nodes ( qid, id, upid, type, pos1, pos2, lnr1, col1, lnr2, col2 )
          values (
            $qid,
            ( select coalesce( max( id ), 0 ) + 1 as id from raw_nodes ),
            $upid, $type, $pos1, $pos2, $lnr1, $col1, $lnr2, $col2 )
          returning *;"""
      #.....................................................................................................
      insert_start_node: @db.prepare SQL"""
        insert into raw_nodes ( qid, id, xtra, upid, type, pos1, pos2, lnr1, col1, lnr2, col2 )
          values (
            $qid, 1, 1, null, 'start', 1, 0, 0, 0, 0, 0 )
          returning *;"""
      #.....................................................................................................
      insert_stop_node: @db.prepare SQL"""
        insert into raw_nodes ( qid, id, xtra, upid, type, pos1, pos2, lnr1, col1, lnr2, col2 )
          values (
            $qid,
            ( select coalesce( max( id ), 0 ) + 1 as id from raw_nodes ),
            1, null, 'stop',
            -- ### TAINT would use CET but fails with "no such column: v.length"
            ( select length + 1 from queries where qid = $qid ),
            ( select length     from queries where qid = $qid ),
            0, 0, 0, 0 )
          returning *;"""
      #.....................................................................................................
    return null

  #---------------------------------------------------------------------------------------------------------
  parse: ( query ) ->
    parser_cfg      =
      doubleQuotedIdentifier: true
    antlr           = { children: [ ( ANTLR.parse query, parser_cfg ).tree, ], }
    R               = { type: 'query', nodes: [], }
    { qid, }        = @statements.insert_query.get { query, }
    R.nodes.push @statements.insert_start_node.get { qid, }
    @_build_tree qid, query, antlr, null, 0, R
    R.nodes.push @statements.insert_stop_node.get { qid, }
    return R

  #---------------------------------------------------------------------------------------------------------
  _build_tree: ( qid, query, antlr, parent, level, tree ) ->
    for branch in antlr.children
      type            = @_type_of_antler_node branch
      position        = @_position_from_branch branch
      txt             = null
      upid            = parent?.id ? null
      flat_node       = { qid, upid, type, position..., }
      @db SQL"savepoint svp_name;"
      flat_node       = @statements.insert_regular_node.get flat_node
      node            = { flat_node..., nodes: [], }
      if branch.children?
        @_build_tree qid, query, branch, flat_node, level + 1, node
      if ( node.type isnt 'terminal' ) and ( node.nodes.length is 0 )
        @db SQL"rollback transaction to savepoint svp_name;" # , { svp_name, }
      else
        @db SQL"release svp_name;"
        tree.nodes.push node
      delete node.nodes if node.nodes.length is 0
    return null

  #---------------------------------------------------------------------------------------------------------
  _type_of_antler_node: ( node ) ->
    R = node.constructor.name
    R = R.replace /(Node|Context)$/, ''
    R = to_snake_case R
    return R

  #---------------------------------------------------------------------------------------------------------
  _position_from_branch: ( branch ) ->
    if branch._symbol?
      pos1  = branch._symbol.start + 1
      lnr1  = branch._symbol._line
      col1  = branch._symbol._charPositionInLine + 1
      pos2  = branch._symbol.stop  + 1
      lnr2  = branch._symbol._line
      col2  = branch._symbol._charPositionInLine + 1 + branch._symbol.stop - branch._symbol.start
    else
      pos1  = null
      lnr1  = null
      col1  = null
      pos2  = null
      lnr2  = null
      col2  = null
    return { pos1, lnr1, col1, pos2, lnr2, col2, }

