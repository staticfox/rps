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

ActiveRecord::Schema.define(version: 2015120220151820) do

  create_table "CommandServ_Commands", primary_key: "Number", force: :cascade do |t|
    t.datetime "Date",                   null: false
    t.text     "Channel",  limit: 65535, null: false
    t.text     "Command",  limit: 65535, null: false
    t.string   "Response", limit: 255,   null: false
  end

  create_table "DNSServ_Exempt", primary_key: "Number", force: :cascade do |t|
    t.string "Server", limit: 40, null: false
  end

  create_table "bot_channels", primary_key: "ID", force: :cascade do |t|
    t.string  "Channel", limit: 50, null: false
    t.integer "Options", limit: 4
  end

  create_table "channels", primary_key: "Number", force: :cascade do |t|
    t.integer "CTime",       limit: 8,     null: false
    t.string  "Channel",     limit: 50,    null: false
    t.string  "Modes",       limit: 25
    t.text    "Topic",       limit: 65535
    t.string  "Topic_setat", limit: 255
    t.string  "Topic_setby", limit: 255
  end

  create_table "limit_serv_channels", id: false, force: :cascade do |t|
    t.integer "Number",  limit: 4,  null: false
    t.string  "Channel", limit: 25, null: false
    t.integer "People",  limit: 4,  null: false
    t.integer "Time",    limit: 8,  null: false
  end

  add_index "limit_serv_channels", ["Number"], name: "Number", unique: true, using: :btree

  create_table "quotes", primary_key: "ID", force: :cascade do |t|
    t.integer "Time",    limit: 4,   null: false
    t.string  "Channel", limit: 50,  null: false
    t.string  "Person",  limit: 50,  null: false
    t.string  "Quote",   limit: 255, null: false
  end

  create_table "rootserv_accesses", force: :cascade do |t|
    t.string  "name",     limit: 255
    t.string  "flags",    limit: 255
    t.string  "added_by", limit: 255
    t.integer "added",    limit: 4
    t.integer "modified", limit: 4
  end

  create_table "user_in_channels", primary_key: "Number", force: :cascade do |t|
    t.string "Channel", limit: 50, null: false
    t.string "User",    limit: 25, null: false
    t.string "Modes",   limit: 25, null: false
  end

  create_table "users", primary_key: "Number", force: :cascade do |t|
    t.text   "Nick",     limit: 65535, null: false
    t.string "CTime",    limit: 15,    null: false
    t.string "UModes",   limit: 25,    null: false
    t.string "Ident",    limit: 15,    null: false
    t.string "CHost",    limit: 75,    null: false
    t.string "IP",       limit: 50,    null: false
    t.string "UID",      limit: 10,    null: false
    t.string "Host",     limit: 100,   null: false
    t.text   "Server",   limit: 65535, null: false
    t.string "NickServ", limit: 25,    null: false
  end

end
