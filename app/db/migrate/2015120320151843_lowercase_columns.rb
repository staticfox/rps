class LowercaseColumns < ActiveRecord::Migration
  def change
    # users table
    rename_column :users, :Nick,     :nick
    rename_column :users, :CTime,    :ctime
    rename_column :users, :UModes,   :umodes
    rename_column :users, :Ident,    :ident
    rename_column :users, :CHost,    :chost
    rename_column :users, :IP,       :ip
    rename_column :users, :UID,      :uid
    rename_column :users, :Host,     :host
    rename_column :users, :Server,   :server
    rename_column :users, :NickServ, :nickserv

    #bot channels
    rename_column :bot_channels, :ID,      :id
    rename_column :bot_channels, :Channel, :channel
    rename_column :bot_channels, :Options, :options

    #channels
    rename_column :channels, :Number,      :number
    rename_column :channels, :CTime,       :ctime
    rename_column :channels, :Channel,     :channel
    rename_column :channels, :Modes,       :modes
    rename_column :channels, :Topic,       :topic
    rename_column :channels, :Topic_setat, :topic_setat
    rename_column :channels, :Topic_setby, :topic_setby

    #limitserv
    rename_column :limit_serv_channels, :Number,  :number
    rename_column :limit_serv_channels, :Channel, :channel
    rename_column :limit_serv_channels, :People,  :people
    rename_column :limit_serv_channels, :Time,    :time

    #quotes
    rename_column :quotes, :ID,      :id
    rename_column :quotes, :Time,    :time
    rename_column :quotes, :Channel, :channel
    rename_column :quotes, :Person,  :person
    rename_column :quotes, :Quote,   :quote

    #users in channels
    rename_column :user_in_channels, :Number,  :number
    rename_column :user_in_channels, :Channel, :channel
    rename_column :user_in_channels, :User,    :user
    rename_column :user_in_channels, :Modes,   :modes
  end
end
