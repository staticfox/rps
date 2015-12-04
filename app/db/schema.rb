# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2015120320152350) do

  create_table "bot_channels", force: :cascade do |t|
    t.string  "channel", limit: 50, null: false
    t.integer "options", limit: 4
  end

  create_table "channels", force: :cascade do |t|
    t.integer "ctime",       limit: 8,     null: false
    t.string  "channel",     limit: 50,    null: false
    t.string  "modes",       limit: 25
    t.text    "topic",       limit: 65535
    t.string  "topic_setat", limit: 255
    t.string  "topic_setby", limit: 255
  end

  create_table "limit_serv_channels", force: :cascade do |t|
    t.string  "channel", limit: 25, null: false
    t.integer "people",  limit: 4,  null: false
    t.integer "time",    limit: 8,  null: false
  end

  add_index "limit_serv_channels", ["id"], name: "Number", unique: true, using: :btree

  create_table "quotes", force: :cascade do |t|
    t.integer "time",    limit: 4,   null: false
    t.string  "channel", limit: 50,  null: false
    t.string  "person",  limit: 50,  null: false
    t.string  "quote",   limit: 255, null: false
  end

  create_table "rootserv_accesses", force: :cascade do |t|
    t.string  "name",     limit: 255
    t.string  "flags",    limit: 255
    t.string  "added_by", limit: 255
    t.integer "added",    limit: 4
    t.integer "modified", limit: 4
  end

  create_table "user_in_channels", force: :cascade do |t|
    t.string "channel", limit: 50, null: false
    t.string "user",    limit: 25, null: false
    t.string "modes",   limit: 25, null: false
  end

  create_table "users", force: :cascade do |t|
    t.text   "nick",     limit: 65535, null: false
    t.string "ctime",    limit: 15,    null: false
    t.string "umodes",   limit: 25,    null: false
    t.string "ident",    limit: 15,    null: false
    t.string "chost",    limit: 75,    null: false
    t.string "ip",       limit: 50,    null: false
    t.string "uid",      limit: 10,    null: false
    t.string "host",     limit: 100,   null: false
    t.text   "server",   limit: 65535, null: false
    t.string "nickserv", limit: 25,    null: false
    t.string "certfp",   limit: 255
  end

end
