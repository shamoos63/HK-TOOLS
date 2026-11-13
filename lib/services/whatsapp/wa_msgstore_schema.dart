// GENERATED from the schema of a WhatsApp for Android 2.26 msgstore.db
// (structure only: tables and views, no rows). Used as the starting database
// when restoring iPhone chats to an Android phone without the phone's own
// backup, the way the commercial transfer tools ship a template.
// ignore_for_file: lines_longer_than_80_chars

/// `CREATE TABLE` / `CREATE VIEW` statements of WhatsApp's msgstore.db,
/// including the shadow tables of its full-text-search tables.
const waMsgstoreSchema = <String>[
  r'''CREATE TABLE props ( _id INTEGER PRIMARY KEY AUTOINCREMENT, key TEXT UNIQUE, value TEXT )''',
  r'''CREATE TABLE message_system_value_change(message_row_id INTEGER PRIMARY KEY,old_data TEXT)''',
  r'''CREATE TABLE message_quoted_media(message_row_id INTEGER PRIMARY KEY,media_job_uuid TEXT,transferred INTEGER,file_path TEXT,file_size INTEGER,media_key BLOB,media_key_timestamp INTEGER,width INTEGER,height INTEGER,direct_path TEXT,message_url TEXT,mime_type TEXT,file_length INTEGER,media_name TEXT,file_hash TEXT,media_duration INTEGER,page_count INTEGER,enc_file_hash TEXT,thumbnail BLOB,media_caption TEXT,accessibility_label TEXT)''',
  r'''CREATE TABLE primary_device_version(user_jid_row_id INTEGER PRIMARY KEY,version INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE TABLE message_external_ad_content(message_row_id INTEGER PRIMARY KEY,title TEXT,body TEXT,media_type INTEGER,thumbnail_url TEXT,full_thumbnail BLOB,micro_thumbnail BLOB,media_url TEXT,source_type TEXT,source_id TEXT,source_url TEXT,render_larger_thumbnail BOOLEAN,show_ad_attribution BOOLEAN,has_icebreaker_auto_response BOOLEAN,has_click_to_call_auto_response BOOLEAN,ad_context_preview_dismissed INTEGER,ctwa_clid TEXT,source_app TEXT,automated_greeting_message_shown INTEGER,greeting_message_body TEXT,cta_payload TEXT,disable_nudge INTEGER,original_image_url TEXT,automated_greeting_message_cta_type TEXT,wtwa_ad_format BOOLEAN, ad_preview_url TEXT, wtwa_website_url TEXT, has_ctwa_flows_auto_response BOOLEAN, agm_thumbnail_strategy INTEGER, agm_title_strategy INTEGER, agm_subtitle_strategy INTEGER, agm_header_interaction_strategy INTEGER, has_ctwa_flows_auto_label BOOLEAN, product_id TEXT)''',
  r'''CREATE TABLE message_quoted_mentions(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER,jid_row_id INTEGER,display_name STRING, mention_type INTEGER)''',
  r'''CREATE TABLE message_quoted_blank_reply(message_row_id INTEGER PRIMARY KEY,parent_group_jid TEXT,group_subject TEXT)''',
  r'''CREATE TABLE message_media_map(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER NOT NULL,chat_row_id INTEGER NOT NULL,media_row_id INTEGER NOT NULL)''',
  r'''CREATE TABLE addon_message_media(_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,message_row_id INTEGER NOT NULL,addon_message_index INTEGER NOT NULL,chat_row_id INTEGER,file_path TEXT,file_size INTEGER,media_key BLOB,media_key_timestamp INTEGER,width INTEGER,height INTEGER,direct_path TEXT,message_url TEXT,mime_type TEXT,file_length INTEGER,file_hash TEXT,enc_file_hash TEXT,partial_media_hash TEXT,partial_media_enc_hash TEXT,original_file_hash TEXT,thumbnail TEXT,thumbnail_direct_path TEXT,thumbnail_hash TEXT,enc_thumbnail_hash TEXT,scans_sidecar BLOB,transferred INTEGER)''',
  r'''CREATE TABLE message_system_event_updates(message_row_id INTEGER PRIMARY KEY,event_message_row_id INTEGER NOT NULL,event_name STRING NOT NULL)''',
  r'''CREATE TABLE business_message_forward_info(message_row_id INTEGER PRIMARY KEY,business_owner_jid_row_id INTEGER NOT NULL)''',
  r'''CREATE TABLE message_system_linked_group_call(message_row_id INTEGER PRIMARY KEY,call_id TEXT,is_video_call INTEGER,call_type INTEGER)''',
  r'''CREATE TABLE quick_replies(_id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT UNIQUE NOT NULL,content TEXT NOT NULL, associated_label_ids TEXT)''',
  r'''CREATE TABLE message_payment_status_update(message_row_id INTEGER PRIMARY KEY,transaction_info TEXT,transaction_data TEXT,init_timestamp TEXT,update_timestamp TEXT,amount_data TEXT)''',
  r'''CREATE TABLE group_notification_version(group_jid_row_id INTEGER PRIMARY KEY,subject_timestamp INTEGER NOT NULL,announcement_version INTEGER NOT NULL,participant_version INTEGER NOT NULL,group_join_request_timestamp INTEGER, group_photo_timestamp INTEGER)''',
  r'''CREATE TABLE mms_thumbnail_metadata(message_row_id INTEGER PRIMARY KEY,direct_path TEXT,media_key BLOB,media_key_timestamp INTEGER,enc_thumb_hash TEXT,thumb_hash TEXT,thumb_width INTEGER,thumb_height INTEGER,transferred INTEGER,micro_thumbnail BLOB,insert_timestamp INTEGER,handle TEXT)''',
  r'''CREATE TABLE audio_data(message_row_id INTEGER PRIMARY KEY,waveform BLOB,background_color INTEGER NOT NULL DEFAULT 0,background_color_changed INTEGER DEFAULT 0,transcription_status INTEGER,transcription_locale INTEGER,transcription_confidence_threshold INTEGER,transcription_request_locale INTEGER,transcription_feedback_submitted INTEGER,transcription_id TEXT)''',
  r'''CREATE TABLE message_system_payment_invite_setup(message_row_id INTEGER PRIMARY KEY,service INTEGER,invite_used INTEGER)''',
  r'''CREATE TABLE media_refs(_id INTEGER PRIMARY KEY AUTOINCREMENT,path TEXT UNIQUE,ref_count INTEGER)''',
  r'''CREATE TABLE message_system_device_change(message_row_id INTEGER PRIMARY KEY,device_added_count INTEGER,device_removed_count INTEGER)''',
  r'''CREATE TABLE bcall_session(_id INTEGER PRIMARY KEY AUTOINCREMENT,session_id TEXT NOT NULL UNIQUE,media_type INTEGER NOT NULL,caption TEXT,master_key BLOB NOT NULL)''',
  r'''CREATE TABLE message_vcard_jid(_id INTEGER PRIMARY KEY AUTOINCREMENT,vcard_jid_row_id INTEGER,vcard_row_id INTEGER,message_row_id INTEGER)''',
  r'''CREATE TABLE integrator_display_name(integrator_id INTEGER PRIMARY KEY NOT NULL,display_name TEXT NOT NULL,status INTEGER NOT NULL,icon_path TEXT NOT NULL DEFAULT '',opt_in_status INTEGER NOT NULL DEFAULT 0,identifier_type INTEGER NOT NULL DEFAULT 0, group_messaging_supported INTEGER)''',
  r'''CREATE TABLE bot_plugin_metadata(message_row_id INTEGER PRIMARY KEY,search_provider INTEGER,plugin_type INTEGER,thumbnail_cdn_url TEXT,profile_photo_cdn_url TEXT,search_provider_url TEXT,reference_index INTEGER,profile_photo_thumbnail BLOB,search_query TEXT,favicon_cdn_url TEXT)''',
  r'''CREATE TABLE message_view_once_media(message_row_id INTEGER PRIMARY KEY,state INTEGER NOT NULL)''',
  r'''CREATE TABLE scheduled_calls(creation_message_row_id INTEGER PRIMARY KEY,key_id TEXT NOT NULL,key_from_me INTEGER NOT NULL,key_chat_row_id INTEGER NOT NULL,call_type INTEGER NOT NULL,scheduled_timestamp INTEGER NOT NULL,call_title TEXT NOT NULL,creator_jid_row_id INTEGER NOT NULL,is_upcoming BOOLEAN NOT NULL,call_log_row_id INTEGER)''',
  r'''CREATE TABLE labels(_id INTEGER PRIMARY KEY AUTOINCREMENT,type INTEGER NOT NULL DEFAULT 0,label_name TEXT,predefined_id INTEGER,color_id INTEGER,sort_id INTEGER NOT NULL DEFAULT 0,hidden INTEGER,mute_end_time INTEGER,mute_schedule_enabled_days INTEGER,mute_schedule_time_from INTEGER,mute_schedule_time_to INTEGER,is_immutable INTEGER, is_aura_benefit_enabled INTEGER, notification_schedule_enabled INTEGER, schedule_mute_outside_enabled INTEGER, schedule_hide_outside_enabled INTEGER, schedule_unmuted_until INTEGER, schedule_unhidden_until INTEGER)''',
  r'''CREATE TABLE messages_hydrated_four_row_template(message_row_id INTEGER PRIMARY KEY,message_template_id TEXT)''',
  r'''CREATE TABLE priority_inbox(_id INTEGER PRIMARY KEY AUTOINCREMENT,priority_score DOUBLE NOT NULL,version INTEGER NOT NULL,chat_row_id INTEGER NOT NULL,is_priority BOOLEAN,label_removed BOOLEAN,time_created INTEGER,deep_conversion_rate BOOLEAN)''',
  r'''CREATE TABLE quick_reply_attachments(_id INTEGER PRIMARY KEY AUTOINCREMENT,quick_reply_id TEXT NOT NULL,uri TEXT NOT NULL,caption TEXT,media_type INTEGER)''',
  r'''CREATE TABLE forwarded_newsletter_message_info(message_row_id INTEGER PRIMARY KEY,newsletter_jid_row_id INTEGER NOT NULL,newsletter_server_message_id INTEGER NOT NULL,newsletter_name TEXT NOT NULL DEFAULT '', profile_name TEXT)''',
  r'''CREATE TABLE message_system_with_group_nodes(message_row_id INTEGER NOT NULL,group_jid_row_id INTEGER NOT NULL,group_node_type INTEGER NOT NULL,group_subject TEXT,version INTEGER,PRIMARY KEY ( message_row_id, group_jid_row_id, group_node_type ))''',
  r'''CREATE TABLE pay_transaction(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER,remote_jid_row_id INTEGER,key_id TEXT,interop_id TEXT,id TEXT,timestamp INTEGER,status INTEGER,error_code TEXT,sender_jid_row_id INTEGER,receiver_jid_row_id INTEGER,type INTEGER,currency_code TEXT,amount_1000,credential_id TEXT,methods TEXT,bank_transaction_id TEXT,metadata TEXT,init_timestamp INTEGER,request_key_id TEXT,country TEXT,version INTEGER,future_data BLOB,service_id INTEGER,background_id TEXT,purchase_initiator INTEGER, receiver_vpa TEXT)''',
  r'''CREATE TABLE media_processed_video(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER,direct_path TEXT,height INTEGER,width INTEGER,file_size INTEGER,bitrate INTEGER,quality INTEGER,capabilities TEXT)''',
  r'''CREATE TABLE message_add_on_pin_in_chat(message_add_on_row_id INTEGER PRIMARY KEY,pin_in_chat_state INTEGER NOT NULL DEFAULT 0,sender_timestamp INTEGER)''',
  r'''CREATE TABLE group_past_participant_user(_id INTEGER PRIMARY KEY AUTOINCREMENT,group_jid_row_id INTEGER NOT NULL,user_jid_row_id INTEGER NOT NULL,is_leave INTEGER NOT NULL,timestamp INTEGER)''',
  r'''CREATE TABLE bot_memory_metadata(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER NOT NULL,memory_annotated_user_message_key_id TEXT NOT NULL,memory TEXT,memory_id TEXT NOT NULL,added INTEGER NOT NULL,bot_jid_row_id INTEGER)''',
  r'''CREATE TABLE message_add_on_reaction(message_add_on_row_id INTEGER PRIMARY KEY,reaction TEXT,sender_timestamp INTEGER)''',
  r'''CREATE TABLE parent_group_participants(parent_group_jid_row_id INTEGER NOT NULL,user_jid_row_id INTEGER NOT NULL)''',
  r'''CREATE TABLE newsletter_message_reaction(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER NOT NULL,reaction TEXT NOT NULL,reaction_count INTEGER NOT NULL)''',
  r'''CREATE TABLE composition(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER NOT NULL,quoted_message_row_id INTEGER,timestamp INTEGER NOT NULL,message_type INTEGER NOT NULL,composition_type INTEGER NOT NULL,text TEXT,lookup_tables INTEGER NOT NULL DEFAULT 0,last_seen_timestamp INTEGER)''',
  r'''CREATE TABLE message_system_scheduled_call_start(message_row_id INTEGER PRIMARY KEY,creation_message_row_id INTEGER NOT NULL UNIQUE,call_title TEXT NOT NULL,call_timestamp_ms INTEGER NOT NULL)''',
  r'''CREATE TABLE payment_background(background_id TEXT PRIMARY KEY,file_size INTEGER,width INTEGER,height INTEGER,mime_type TEXT,placeholder_color INTEGER,text_color INTEGER,subtext_color INTEGER,fullsize_url TEXT,description TEXT,lg TEXT,media_key BLOB,media_key_timestamp INTEGER,file_sha256 TEXT,file_enc_sha256 TEXT,direct_path TEXT)''',
  r'''CREATE TABLE message_parent_association(message_row_id INTEGER PRIMARY KEY,parent_message_row_id INTEGER NOT NULL,association_type INTEGER NOT NULL)''',
  r'''CREATE TABLE group_participant_label_metadata(group_participant_user_row_id INTEGER PRIMARY KEY,edit_time DATETIME NOT NULL)''',
  r'''CREATE TABLE call_log(_id INTEGER PRIMARY KEY AUTOINCREMENT,jid_row_id INTEGER,from_me INTEGER,call_id TEXT,transaction_id INTEGER,timestamp INTEGER,video_call INTEGER,duration INTEGER,call_result INTEGER,is_dnd_mode_on INTEGER,bytes_transferred INTEGER,group_jid_row_id INTEGER NOT NULL DEFAULT 0,is_joinable_group_call INTEGER,call_creator_device_jid_row_id INTEGER NOT NULL DEFAULT 0,call_random_id TEXT,call_link_row_id INTEGER NOT NULL DEFAULT 0,call_type INTEGER,offer_silence_reason INTEGER,scheduled_id TEXT, telecom_uuid TEXT, terminated_by_device_switch INTEGER)''',
  r'''CREATE TABLE message_forwarded(message_row_id INTEGER PRIMARY KEY,forward_score INTEGER, forward_origin INTEGER)''',
  r'''CREATE TABLE newsletter_my_reaction_orphan_message(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER NOT NULL,server_message_id INTEGER NOT NULL,reaction_from_me TEXT,reactions_from_me_ts INTEGER,votes_from_me TEXT,votes_from_me_ts INTEGER)''',
  r'''CREATE TABLE optimised_delivery_info(message_row_id INTEGER PRIMARY KEY,msg_disclosed_token TEXT,msg_undisclosed_token TEXT,msg_timestamp_v2 INTEGER,token_timestamp LONG,business_jid_row_id INTEGER NOT NULL)''',
  r'''CREATE TABLE smart_suggestions_key_value(_id INTEGER PRIMARY KEY AUTOINCREMENT,key TEXT UNIQUE,value BLOB)''',
  r'''CREATE TABLE status_notification_info(message_row_id INTEGER PRIMARY KEY,response_status_row_id INTEGER NOT NULL,original_status_row_id INTEGER NOT NULL,type INTEGER NOT NULL)''',
  r'''CREATE TABLE message_quoted(message_row_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER NOT NULL,parent_message_chat_row_id INTEGER NOT NULL,from_me INTEGER NOT NULL,sender_jid_row_id INTEGER,key_id TEXT NOT NULL,timestamp INTEGER,message_type INTEGER,origin INTEGER,text_data TEXT,payment_transaction_id TEXT,lookup_tables INTEGER, quoted_source INTEGER, quoted_type INTEGER)''',
  r'''CREATE TABLE message_link(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER,message_row_id INTEGER,link_index INTEGER)''',
  r'''CREATE TABLE message_system_biz_per_customer_3pd_data_share_state(message_row_id INTEGER PRIMARY KEY,data_sharing_enabled BOOLEAN)''',
  r'''CREATE TABLE receipt_device(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER NOT NULL,receipt_device_jid_row_id INTEGER NOT NULL,receipt_device_timestamp INTEGER,primary_device_version INTEGER)''',
  r'''CREATE TABLE message_system_reminder_setup(message_row_id INTEGER PRIMARY KEY,original_message_row_id INTEGER NOT NULL UNIQUE,reminder_timestamp_ms INTEGER NOT NULL,reminder_content TEXT NOT NULL)''',
  r'''CREATE TABLE message_order(message_row_id INTEGER PRIMARY KEY,order_id TEXT,thumbnail BLOB,order_title TEXT,item_count INTEGER,status INTEGER,surface INTEGER,message TEXT,seller_jid INTEGER,token TEXT,currency_code TEXT,total_amount_1000 INTEGER,message_version INTEGER,catalog_type TEXT)''',
  r'''CREATE TABLE message_limit_sharing_setting(message_row_id INTEGER PRIMARY KEY,enabled INTEGER,trigger INTEGER)''',
  r'''CREATE TABLE message_ui_elements(_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,message_row_id INTEGER NOT NULL,element_type INTEGER,element_content TEXT, description TEXT, template_id TEXT, hsm_tag TEXT, footer_text TEXT, button_text TEXT, message_type INTEGER)''',
  r'''CREATE TABLE message_system_lid_change(message_row_id INTEGER PRIMARY KEY,old_lid_row_id INTEGER,new_lid_row_id INTEGER,display_name TEXT)''',
  r'''CREATE TABLE keywords(_id INTEGER PRIMARY KEY AUTOINCREMENT,keyword TEXT UNIQUE NOT NULL)''',
  r'''CREATE TABLE message_sticker_pack(message_row_id INTEGER PRIMARY KEY,sticker_pack_id TEXT NOT NULL,tray_icon_file_name TEXT NOT NULL,pack_name TEXT NOT NULL,pack_description TEXT,publisher TEXT,image_data_hash TEXT,sticker_pack_size INTEGER,sticker_pack_origin INTEGER)''',
  r'''CREATE TABLE receipt_orphaned(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER NOT NULL,from_me INTEGER NOT NULL,key_id TEXT NOT NULL,receipt_device_jid_row_id INTEGER NOT NULL,receipt_recipient_jid_row_id INTEGER,status INTEGER,timestamp INTEGER)''',
  r'''CREATE TABLE mms_metadata(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER,direct_path TEXT,media_key BLOB,media_key_timestamp INTEGER,enc_thumb_hash TEXT,thumb_hash TEXT,thumb_width INTEGER,thumb_height INTEGER,transferred INTEGER,micro_thumbnail BLOB,insert_timestamp INTEGER,handle TEXT,type INTEGER)''',
  r'''CREATE TABLE transcription_segment(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER NOT NULL,substring_start INTEGER NOT NULL,substring_length INTEGER NOT NULL,timestamp INTEGER,duration INTEGER,confidence INTEGER)''',
  r'''CREATE TABLE message_streaming_sidecar(message_row_id INTEGER PRIMARY KEY,sidecar BLOB,chunk_lengths BLOB,timestamp INTEGER)''',
  r'''CREATE TABLE message_add_on_poll_vote(message_add_on_row_id INTEGER PRIMARY KEY,sender_timestamp INTEGER)''',
  r'''CREATE TABLE call_link(_id INTEGER PRIMARY KEY AUTOINCREMENT,token TEXT NOT NULL,creator_jid_row_id INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE TABLE reporting_info(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER NOT NULL,reporting_tag BLOB NOT NULL,stanza_id STRING,send_timestamp LONG,receive_timestamp LONG,stanza_id_text TEXT,receive_flow INTEGER, is_message_add_on INTEGER)''',
  r'''CREATE TABLE message_system_opt_out(message_row_id INTEGER PRIMARY KEY,biz_opt_out_category INTEGER,biz_opt_out_action INTEGER)''',
  r'''CREATE TABLE message_secret(message_row_id INTEGER PRIMARY KEY,message_secret BLOB)''',
  r'''CREATE TABLE bot_message_prompts(message_row_id INTEGER PRIMARY KEY,chat_row_id INTEGER UNIQUE,prompts TEXT,impression_logged INTEGER DEFAULT 0)''',
  r'''CREATE TABLE message_template_quoted(message_row_id INTEGER PRIMARY KEY,content_text_data TEXT NOT NULL,footer_text_data TEXT)''',
  r'''CREATE TABLE payment_link_metadata(message_row_id INTEGER PRIMARY KEY,link_header_type INTEGER,cta_button_text TEXT, params_json TEXT)''',
  r'''CREATE TABLE newsletter_linked_account(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER NOT NULL,name TEXT NOT NULL,link TEXT NOT NULL)''',
  r'''CREATE TABLE missed_call_logs(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER,timestamp INTEGER,video_call INTEGER,group_jid_row_id INTEGER NOT NULL DEFAULT 0,is_joinable_group_call INTEGER,is_dnd_mode_on INTEGER,offer_silence_reason INTEGER)''',
  r'''CREATE TABLE message_album(message_row_id INTEGER PRIMARY KEY,image_count INTEGER NOT NULL DEFAULT 0,video_count INTEGER NOT NULL DEFAULT 0, expected_image_count INTEGER, expected_video_count INTEGER)''',
  r'''CREATE TABLE suggest_as_you_type(message_row_id INTEGER PRIMARY KEY)''',
  r'''CREATE TABLE lid_display_name(lid_row_id INTEGER PRIMARY KEY NOT NULL,display_name TEXT NOT NULL,username TEXT)''',
  r'''CREATE TABLE message_system_chat_assignment(message_row_id INTEGER PRIMARY KEY,agent_name TEXT,is_unassigned_chat INTEGER)''',
  r'''CREATE TABLE message_orphaned_edit(_id INTEGER PRIMARY KEY,key_id TEXT NOT NULL,from_me INTEGER NOT NULL,chat_row_id INTEGER NOT NULL,sender_jid_row_id INTEGER NOT NULL DEFAULT 0,timestamp INTEGER,message_type INTEGER NOT NULL,revoked_key_id TEXT,retry_count INTEGER,admin_jid_row_id INTEGER,orphan_message_data BLOB,reporting_token BLOB,reporting_tag BLOB,reporting_version INTEGER, biz_bot_thinking_state INTEGER, poll_add_option_revoke INTEGER)''',
  r'''CREATE TABLE ai_rich_response_message_additional_info(message_row_id INTEGER PRIMARY KEY,ai_rich_response_additional_blob BLOB)''',
  r'''CREATE TABLE lid_chat_state(jid_row_id INTEGER PRIMARY KEY NOT NULL,is_pn_shared INTEGER NOT NULL DEFAULT 0,pn_requested_ts INTEGER NOT NULL DEFAULT 0,pnh_duplicate_lid_thread INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE TABLE backup_changes(_id INTEGER PRIMARY KEY AUTOINCREMENT,operation TEXT NOT NULL,table_name TEXT NOT NULL,table_row_id INTEGER NOT NULL)''',
  r'''CREATE TABLE message_add_on_event_response(message_add_on_row_id INTEGER PRIMARY KEY,response INTEGER DEFAULT 0,sender_timestamp INTEGER NOT NULL,extra_guest_count INTEGER)''',
  r'''CREATE TABLE message_payment(message_row_id INTEGER PRIMARY KEY,sender_jid_row_id INTEGER,receiver_jid_row_id INTEGER,amount_with_symbol TEXT,remote_resource TEXT,remote_message_sender_jid_row_id INTEGER,remote_message_from_me INTEGER,remote_message_key TEXT)''',
  r'''CREATE TABLE message_event(message_row_id INTEGER PRIMARY KEY,is_canceled INTEGER DEFAULT 0,name TEXT NOT NULL,description TEXT,location_latitude REAL,location_longitude REAL,location_name TEXT,location_address TEXT,join_link TEXT,start_time DATETIME NOT NULL,end_time DATETIME,chat_row_id INTEGER,event_state INTEGER NOT NULL DEFAULT 0,allow_extra_guests INTEGER,is_schedule_call INTEGER, has_reminder INTEGER, reminder_offset_sec INTEGER, show_upcoming_banner INTEGER)''',
  r'''CREATE TABLE message_add_on_poll_vote_selected_option(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_add_on_row_id INTEGER,message_poll_option_id INTEGER)''',
  r'''CREATE TABLE message_system_group(message_row_id INTEGER PRIMARY KEY,is_me_joined INTEGER)''',
  r'''CREATE TABLE message_quoted_ui_elements_reply(message_row_id INTEGER PRIMARY KEY,element_type INTEGER,reply_values TEXT,reply_description TEXT)''',
  r'''CREATE TABLE message_system_business_broadcast(message_row_id INTEGER PRIMARY KEY,broadcast_raw_jid STRING NOT NULL)''',
  r'''CREATE TABLE premium_message_info(message_row_id INTEGER PRIMARY KEY,campaign_id STRING NOT NULL,chat_row_id INTEGER,account_jid_row_id INTEGER)''',
  r'''CREATE TABLE url_tracking_map_element(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER NOT NULL,original_url TEXT,consented_users_url TEXT,unconsented_users_url TEXT,card_index INTEGER)''',
  r'''CREATE TABLE message_template_button(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER,text_data TEXT NOT NULL,extra_data TEXT,button_type INTEGER,used INTEGER,selected_index INTEGER,selected_carousel_card_index INTEGER,otp_button_type INTEGER,extra_consent_data TEXT,otp_matched_package_name TEXT,webview_presentation INTEGER,webview_interaction INTEGER)''',
  r'''CREATE TABLE message_location(message_row_id INTEGER PRIMARY KEY,chat_row_id INTEGER,latitude REAL,longitude REAL,place_name TEXT,place_address TEXT,url TEXT,live_location_share_duration INTEGER,live_location_sequence_number INTEGER,live_location_final_latitude REAL,live_location_final_longitude REAL,live_location_final_timestamp INTEGER,map_download_status INTEGER)''',
  r'''CREATE TABLE message_system_biz_callback_enabled(message_row_id INTEGER PRIMARY KEY,callback_expiry_timestamp INTEGER,outgoing_failed_call_id TEXT)''',
  r'''CREATE TABLE message_status_psa_campaign(message_row_id INTEGER PRIMARY KEY,campaign_id TEXT,duration INTEGER,first_seen_timestamp INTEGER,action_link_url TEXT,action_link_button_title TEXT)''',
  r'''CREATE TABLE agent_message_attribution(message_row_id INTEGER PRIMARY KEY,agent_id TEXT NOT NULL)''',
  r'''CREATE TABLE template_messages_metadata(message_row_id INTEGER PRIMARY KEY,message_template_id TEXT,message_hsm_tag TEXT,message_source_type TEXT,message_delivery_decision_id TEXT, message_delivery_decision_sources TEXT)''',
  r'''CREATE TABLE missed_call_log_participant(_id INTEGER PRIMARY KEY AUTOINCREMENT,call_logs_row_id INTEGER,jid TEXT,call_result INTEGER)''',
  r'''CREATE TABLE support_citation_metadata(message_row_id INTEGER PRIMARY KEY,help_article_citations TEXT)''',
  r'''CREATE TABLE message_media_vcard_count(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER,count INTEGER)''',
  r'''CREATE TABLE message_comment(_id INTEGER PRIMARY KEY AUTOINCREMENT,parent_message_row_id INTEGER,message_row_id INTEGER)''',
  r'''CREATE TABLE labeled_jid(_id INTEGER PRIMARY KEY AUTOINCREMENT,label_id INTEGER NOT NULL,jid_row_id INTEGER NOT NULL)''',
  r'''CREATE TABLE message_media_interactive_annotation_embedded_music(message_media_interactive_annotation_row_id INTEGER PRIMARY KEY,music_content_media_id TEXT,song_id TEXT,author TEXT,title TEXT,artwork_direct_path TEXT,artwork_sha256 BLOB,artwork_enc_sha256 BLOB,artwork_media_key BLOB,artist_attribution TEXT,country_blocklist BLOB,is_explicit INTEGER, pending_embedded_music_type INTEGER, start_time_ms INTEGER, derived_content_start_time_ms INTEGER, overlap_duration_ms INTEGER, audio_library_product TEXT)''',
  r'''CREATE TABLE message_add_on_receipt_device(receipt_device_id INTEGER PRIMARY KEY AUTOINCREMENT,message_add_on_row_id INTEGER,receipt_device_jid_row_id INTEGER,receipt_device_timestamp INTEGER,primary_device_version INTEGER)''',
  r'''CREATE TABLE quick_reply_keywords(_id INTEGER PRIMARY KEY AUTOINCREMENT,quick_reply_id TEXT NOT NULL,keyword_id TEXT NOT NULL)''',
  r'''CREATE TABLE message_system_group_with_parent(message_row_id INTEGER PRIMARY KEY,linked_parent_group_name TEXT)''',
  r'''CREATE TABLE message_quoted_call_log(message_row_id INTEGER PRIMARY KEY,video_call BOOLEAN,call_result INTEGER)''',
  r'''CREATE TABLE message_payment_transaction_reminder(message_row_id INTEGER PRIMARY KEY,web_stub TEXT,amount TEXT,transfer_date TEXT,payment_sender_name TEXT,expiration INTEGER,remote_message_key TEXT)''',
  r'''CREATE TABLE newsletter_message(message_row_id INTEGER PRIMARY KEY,chat_row_id INTEGER NOT NULL,server_message_id INTEGER NOT NULL,comments_count INTEGER NOT NULL DEFAULT 0,reaction_from_me TEXT,extra_newsletter_tables INTEGER NOT NULL DEFAULT 0,extra_table_last_update_ts INTEGER,reactions_from_me_ts INTEGER,view_count INTEGER,is_autodelete_eligible INTEGER,is_wamo_sub INTEGER, forwards_count INTEGER, admin_profile_id INTEGER, admin_profile_name TEXT, admin_profile_picture_id INTEGER, admin_profile_picture_url TEXT, is_paid_partnership INTEGER)''',
  r'''CREATE TABLE invoice_transactions(message_row_id INTEGER PRIMARY KEY,pay_transaction_id INTEGER)''',
  r'''CREATE TABLE message_edit_info(message_row_id INTEGER PRIMARY KEY,original_key_id TEXT NOT NULL,edited_timestamp INTEGER NOT NULL,sender_timestamp INTEGER NOT NULL)''',
  r'''CREATE TABLE status_message_info(message_row_id INTEGER PRIMARY KEY,status_distribution_mode INTEGER NOT NULL,is_mentioned INTEGER,status_mentions TEXT,status_mention_source TEXT,cannot_receive_reactions INTEGER,cannot_be_ranked INTEGER,has_embedded_music INTEGER,status_attribution_type INTEGER,is_group_status INTEGER,can_be_reshared INTEGER,ranking_version INTEGER,external_media_duration_seconds INTEGER,original_status_message_row_id INTEGER, original_poster_notification_type INTEGER, status_source_type INTEGER, selected_audience_list TEXT, override_notification_recipient_jid TEXT, can_receive_multi_reactions INTEGER, audience_type INTEGER, status_poster_contact_type INTEGER, status_audience_custom_list_name TEXT, status_audience_custom_list_emoji TEXT, poster_status_id TEXT)''',
  r'''CREATE TABLE message_quote_invoice(message_row_id INTEGER PRIMARY KEY,amount TEXT NOT NULL,note TEXT NOT NULL,status INTEGER,attachment_jpeg_thumbnail BLOB)''',
  r'''CREATE TABLE message(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER NOT NULL,from_me INTEGER NOT NULL,key_id TEXT NOT NULL,sender_jid_row_id INTEGER,status INTEGER,broadcast INTEGER,recipient_count INTEGER,participant_hash TEXT,origination_flags INTEGER,origin INTEGER,timestamp INTEGER,received_timestamp INTEGER,receipt_server_timestamp INTEGER,message_type INTEGER,text_data TEXT,starred INTEGER,lookup_tables INTEGER,message_add_on_flags INTEGER,view_mode INTEGER,sort_id INTEGER NOT NULL DEFAULT 0,translated_text TEXT, view_replies_thread_id INTEGER, server_sts INTEGER)''',
  r'''CREATE TABLE message_media(message_row_id INTEGER PRIMARY KEY,chat_row_id INTEGER,autotransfer_retry_enabled INTEGER,multicast_id TEXT,media_job_uuid TEXT,transferred INTEGER,transcoded INTEGER,file_path TEXT,file_size INTEGER,suspicious_content INTEGER,trim_from INTEGER,trim_to INTEGER,face_x INTEGER,face_y INTEGER,media_key BLOB,media_key_timestamp INTEGER,width INTEGER,height INTEGER,has_streaming_sidecar INTEGER,gif_attribution INTEGER,thumbnail_height_width_ratio REAL,direct_path TEXT,first_scan_sidecar BLOB,first_scan_length INTEGER,message_url TEXT,mime_type TEXT,file_length INTEGER,media_name TEXT,file_hash TEXT,media_duration INTEGER,page_count INTEGER,enc_file_hash TEXT,partial_media_hash TEXT,partial_media_enc_hash TEXT,is_animated_sticker INTEGER,original_file_hash TEXT,mute_video INTEGER DEFAULT 0,media_caption TEXT,media_upload_handle TEXT,sticker_flags INTEGER,raw_transcription_text TEXT,first_viewed_timestamp INTEGER,doodle_id TEXT,media_source_type INTEGER,accessibility_label TEXT,media_transcode_quality INTEGER DEFAULT 0, metadata_url TEXT, motion_photo_presentation_offset_ms INTEGER, qr_url TEXT, media_key_domain INTEGER, e2ee_media_key BLOB, premium_message INTEGER, emoji_tags TEXT, is_offloaded INTEGER, dash_manifest_url TEXT)''',
  r'''CREATE TABLE message_system_group_auto_restrict(message_row_id INTEGER PRIMARY KEY,threshold INTEGER)''',
  r'''CREATE TABLE message_orphan(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER,from_me INTEGER,key_id TEXT NOT NULL,sender_jid_row_id INTEGER,parent_chat_row_id INTEGER,parent_from_me INTEGER,parent_key_id TEXT,parent_sender_jid_row_id INTEGER,timestamp INTEGER,orphan_message_data BLOB,orphan_message_type INTEGER,orphan_message_stanza_data BLOB,orphan_message_reason INTEGER)''',
  r'''CREATE TABLE suggested_replies(message_row_id INTEGER PRIMARY KEY,customer_message_row_id INTEGER NOT NULL,tokenized_customer_message STRING,customer_message_embedding BLOB)''',
  r'''CREATE TABLE message_system_community_link_changed(message_row_id INTEGER PRIMARY KEY,old_group_type INTEGER,new_group_type INTEGER NOT NULL,linked_parent_group_jid_row_id INTEGER)''',
  r'''CREATE TABLE message_system_chat_participant(message_row_id INTEGER,user_jid_row_id INTEGER)''',
  r'''CREATE TABLE call_log_participant_v2(_id INTEGER PRIMARY KEY AUTOINCREMENT,call_log_row_id INTEGER,jid_row_id INTEGER,call_result INTEGER)''',
  r'''CREATE TABLE message_comment_parent(message_row_id INTEGER PRIMARY KEY,chat_row_id INTEGER,number_of_comments INTEGER NOT NULL,last_comment_ts INTEGER,last_comment_message_row_id INTEGER)''',
  r'''CREATE TABLE message_future(message_row_id INTEGER PRIMARY KEY,version INTEGER,data BLOB,future_message_type INTEGER,future_proof_stanza BLOB,edit_version INTEGER,message_stanza_data BLOB)''',
  r'''CREATE TABLE scheduled_reminder_message(message_row_id INTEGER PRIMARY KEY,scheduled_reminder_timestamp_ms INTEGER NOT NULL,chat_row_id INTEGER)''',
  r'''CREATE TABLE message_quoted_group_invite(message_row_id INTEGER PRIMARY KEY,group_jid_row_id INTEGER NOT NULL,admin_jid_row_id INTEGER NOT NULL,group_name TEXT,invite_code TEXT,expiration INTEGER,invite_time INTEGER,expired INTEGER,group_type INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE TABLE group_participant_user(_id INTEGER PRIMARY KEY AUTOINCREMENT,group_jid_row_id INTEGER NOT NULL,user_jid_row_id INTEGER NOT NULL,rank INTEGER,pending INTEGER,add_timestamp INTEGER,label TEXT, join_method INTEGER, group_history_send_state INTEGER)''',
  r'''CREATE TABLE newsletter(chat_row_id INTEGER PRIMARY KEY,name TEXT NOT NULL,name_id INTEGER NOT NULL,description TEXT NOT NULL,description_id INTEGER NOT NULL,picture_url TEXT,picture_id INTEGER NOT NULL,preview_url TEXT,preview_id INTEGER NOT NULL,invite_code TEXT,handle TEXT,subscribers_count INTEGER NOT NULL,membership INTEGER NOT NULL,privacy INTEGER NOT NULL,verified INTEGER NOT NULL,muted INTEGER NOT NULL,oldest_message_retrieved INTEGER NOT NULL,suspended INTEGER NOT NULL DEFAULT 0,deleted INTEGER NOT NULL DEFAULT 0,show_enforced_update_banner INTEGER,reaction_setting INTEGER,reaction_setting_blocklist STRING,reaction_setting_update_ts INTEGER,verification_source INTEGER,admin_count INTEGER,capabilities INTEGER,wamo_sub_plan_id INTEGER,wamo_sub_status INTEGER,fts_index_state INTEGER,last_fts_message_indexed INTEGER, admin_activity_tone TEXT, follower_activity_tone TEXT, admin_activity_vibrate INTEGER, follower_activity_vibrate INTEGER, admin_profile_id INTEGER, admin_profile_name TEXT, admin_profile_picture_id INTEGER, admin_profile_picture_url TEXT, last_status_server_id INTEGER, last_filled_status_server_id INTEGER, refresh_after_interval_sec INTEGER, admin_profiles_enabled INTEGER, last_status_sent_time INTEGER)''',
  r'''CREATE TABLE jid(_id INTEGER PRIMARY KEY AUTOINCREMENT,user TEXT NOT NULL,server TEXT NOT NULL,agent INTEGER,device INTEGER,type INTEGER,raw_string TEXT)''',
  r'''CREATE TABLE payment_background_order(background_id TEXT PRIMARY KEY,background_order INTEGER)''',
  r'''CREATE TABLE message_ui_elements_reply(message_row_id INTEGER PRIMARY KEY,element_type INTEGER,reply_values TEXT,reply_description TEXT,flow_id TEXT)''',
  r'''CREATE TABLE composition_media(composition_row_id INTEGER PRIMARY KEY NOT NULL,media_uri TEXT,media_duration_in_seconds INTEGER,media_name TEXT,file_length INTEGER)''',
  r'''CREATE TABLE away_messages(_id INTEGER PRIMARY KEY AUTOINCREMENT,jid TEXT UNIQUE NOT NULL)''',
  r'''CREATE TABLE jid_map(lid_row_id INTEGER PRIMARY KEY NOT NULL,jid_row_id INTEGER NOT NULL,sort_id INTEGER)''',
  r'''CREATE TABLE message_system(message_row_id INTEGER PRIMARY KEY,action_type INTEGER NOT NULL)''',
  r'''CREATE TABLE message_system_reminder_sent(message_row_id INTEGER PRIMARY KEY,original_message_row_id INTEGER NOT NULL UNIQUE,original_reminder_content TEXT NOT NULL)''',
  r'''CREATE TABLE message_system_business_state(message_row_id INTEGER PRIMARY KEY,privacy_message_type INTEGER NOT NULL,business_name TEXT, is_deprecated INTEGER)''',
  r'''CREATE TABLE newsletter_subscribers(_id INTEGER PRIMARY KEY,chat_row_id INTEGER NOT NULL,jid_row_id INTEGER,display_name TEXT,profile_picture_direct_path TEXT,subscription_time INTEGER,role INTEGER NOT NULL DEFAULT 0,type_of_fetch INTEGER NOT NULL DEFAULT 0,fetched_time INTEGER NOT NULL DEFAULT 0, admin_profile_id TEXT, admin_profile_name TEXT, admin_profile_picture_id INTEGER, admin_profile_picture_url TEXT)''',
  r'''CREATE TABLE bot_chat_info(chat_row_id INTEGER PRIMARY KEY,welcome_request_message_sent BOOLEAN,bot_metrics_thread_origin TEXT)''',
  r'''CREATE TABLE joinable_call_log(call_log_row_id INTEGER PRIMARY KEY,call_id TEXT NOT NULL,joinable_video_call INTEGER NOT NULL DEFAULT 0,group_jid_row_id INTEGER NOT NULL DEFAULT 0,phash_identifier TEXT, self_other_device_connected INTEGER, is_lgc_add INTEGER)''',
  r'''CREATE TABLE status_crossposting_v3(status_message_row_id INTEGER,crossposting_session_id TEXT,crossposting_status_unique_id TEXT,state INTEGER,media_file_path TEXT,direct_url_path TEXT,destination INTEGER,PRIMARY KEY (status_message_row_id, destination))''',
  r'''CREATE TABLE ai_rich_response_message_core_info(message_row_id INTEGER PRIMARY KEY,ai_rich_response_message_type INTEGER NOT NULL DEFAULT 0,ai_rich_response_submessage_types TEXT NOT NULL DEFAULT '',additional_table_mask INTEGER NOT NULL DEFAULT 0,ai_rich_response_core_blob BLOB,planning_status INTEGER,foa_native_data BLOB, foa_native_mutation BLOB, foa_native_mutation_extended BLOB, foa_native_original_recipient_metadata BLOB)''',
  r'''CREATE TABLE message_ephemeral(message_row_id INTEGER PRIMARY KEY,duration INTEGER NOT NULL,expire_timestamp INTEGER NOT NULL,keep_in_chat INTEGER NOT NULL DEFAULT 0,ephemeral_trigger INTEGER,ephemeral_initiated_by_me INTEGER, after_read_duration INTEGER)''',
  r'''CREATE TABLE message_bot_feedback(message_row_id INTEGER PRIMARY KEY,bot_feedback_kind INTEGER NOT NULL,bot_feedback_text TEXT NOT NULL,bot_feedback_key_remote_jid TEXT NOT NULL,bot_feedback_key_from_me INTEGER NOT NULL,bot_feedback_key_id TEXT NOT NULL,bot_feedback_kind_positive INTEGER NOT NULL DEFAULT 0,bot_feedback_kind_negative INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE TABLE message_quoted_product(message_row_id INTEGER PRIMARY KEY,business_owner_jid INTEGER,product_id TEXT,title TEXT,description TEXT,currency_code TEXT,amount_1000 INTEGER,retailer_id TEXT,url TEXT,signed_url TEXT,product_image_count INTEGER,sale_amount_1000 INTEGER,body TEXT,footer TEXT)''',
  r'''CREATE TABLE message_text(message_row_id INTEGER PRIMARY KEY,description TEXT,page_title TEXT,url TEXT,font_style INTEGER,text_color INTEGER,background_color INTEGER,preview_type INTEGER,invite_link_group_type INTEGER NOT NULL DEFAULT 0,counter_abuse_token TEXT,fb_experiment_id INTEGER, social_media_post_type INTEGER, link_media_duration_seconds INTEGER, link_end_index INTEGER)''',
  r'''CREATE TABLE bot_message_info(message_row_id INTEGER PRIMARY KEY,target_id TEXT,message_state INTEGER DEFAULT 0,invoker_jid_row_id INTEGER,model_type INTEGER,message_disclaimer TEXT,keyword_json TEXT,promotion_message TEXT, imagine_json TEXT, age_collection INTEGER, bot_response_id TEXT, bot_jid_row_id INTEGER, in_app_thread_survey TEXT, verification_metadata BLOB, response_viewed INTEGER, bot_group_json TEXT, metrics_metadata_json TEXT, bot_deep_link_token TEXT, ai_media_collection_metadata_json TEXT, signature_validation_status INTEGER, tool_calls_blob BLOB, bot_history_share_json TEXT, bot_client_public_key TEXT, message_origin_json TEXT, hatch_metadata BLOB)''',
  r'''CREATE TABLE jid_user_metadata(jid_row_id INTEGER PRIMARY KEY NOT NULL,country_code TEXT)''',
  r'''CREATE TABLE message_quoted_payment_invite(message_row_id INTEGER PRIMARY KEY,service INTEGER,expiration_timestamp INTEGER, incentive_eligible INTEGER, referral_id TEXT, invite_type INTEGER)''',
  r'''CREATE TABLE message_details(message_row_id INTEGER PRIMARY KEY,author_device_jid INTEGER)''',
  r'''CREATE TABLE favorite(_id INTEGER PRIMARY KEY AUTOINCREMENT,jid_row_id INTEGER UNIQUE,favorite_type INTEGER,sort_order INTEGER)''',
  r'''CREATE TABLE message_add_on_keep_in_chat(message_add_on_row_id INTEGER PRIMARY KEY,keep_in_chat_state INTEGER NOT NULL DEFAULT 0,sender_timestamp INTEGER,keep_count INTEGER NOT NULL DEFAULT 0,actor_device_jid_row_id INTEGER)''',
  r'''CREATE TABLE status(_id INTEGER PRIMARY KEY AUTOINCREMENT,jid_row_id INTEGER UNIQUE,message_table_id INTEGER,last_read_message_table_id INTEGER,last_read_receipt_sent_message_table_id INTEGER,first_unread_message_table_id INTEGER,autodownload_limit_message_table_id INTEGER,timestamp INTEGER,unseen_count INTEGER,total_count INTEGER, unseen_count_close_friends INTEGER)''',
  r'''CREATE TABLE message_newsletter_admin_invite(message_row_id INTEGER PRIMARY KEY,newsletter_jid_row_id INTEGER NOT NULL,newsletter_name TEXT NOT NULL,expiration INTEGER NOT NULL)''',
  r'''CREATE TABLE message_scheduled_call(message_row_id INTEGER PRIMARY KEY,scheduled_timestamp_ms INTEGER,call_type INTEGER,title TEXT)''',
  r'''CREATE TABLE group_participant_device(_id INTEGER PRIMARY KEY AUTOINCREMENT,group_participant_row_id INTEGER NOT NULL,device_jid_row_id INTEGER NOT NULL,sent_sender_key INTEGER,sent_add_on_sender_key INTEGER, sent_sender_key_bucket TEXT)''',
  r'''CREATE TABLE message_system_initial_privacy_provider(message_row_id INTEGER PRIMARY KEY,privacy_provider INTEGER NOT NULL DEFAULT 0,verified_biz_name TEXT,biz_state_id INTEGER, is_deprecated INTEGER)''',
  r'''CREATE TABLE receipt_user(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER NOT NULL,receipt_user_jid_row_id INTEGER NOT NULL,receipt_timestamp INTEGER,read_timestamp INTEGER,played_timestamp INTEGER)''',
  r'''CREATE TABLE message_add_on_scheduled_call_edit(message_add_on_row_id INTEGER PRIMARY KEY,edit_type INTEGER NOT NULL DEFAULT 0,message_edit_version INTEGER)''',
  r'''CREATE TABLE message_quoted_order(message_row_id INTEGER PRIMARY KEY,order_id TEXT,thumbnail BLOB,order_title TEXT,item_count INTEGER,status INTEGER,surface INTEGER,message TEXT,seller_jid INTEGER,token TEXT,currency_code TEXT,total_amount_1000 INTEGER,message_version INTEGER,catalog_type TEXT)''',
  r'''CREATE TABLE message_broadcast_ephemeral(message_row_id INTEGER PRIMARY KEY,shared_secret BLOB NOT NULL)''',
  r'''CREATE TABLE message_thumbnail(message_row_id INTEGER PRIMARY KEY,thumbnail BLOB)''',
  r'''CREATE TABLE message_product(message_row_id INTEGER PRIMARY KEY,business_owner_jid INTEGER,product_id TEXT,title TEXT,description TEXT,currency_code TEXT,amount_1000 INTEGER,retailer_id TEXT,url TEXT,signed_url TEXT,product_image_count INTEGER,sale_amount_1000 INTEGER,body TEXT,footer TEXT)''',
  r'''CREATE TABLE message_ephemeral_sync_response(chat_jid TEXT PRIMARY KEY NOT NULL,last_sync_response_sent_timestamp INTEGER NOT NULL,no_of_retries_sent_already INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE TABLE message_poll_option(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER,option_sha256 TEXT,option_name TEXT,vote_total INTEGER,option_hash TEXT, contributor_jid_row_id INTEGER, added_timestamp_ms INTEGER, add_option_message_row_id INTEGER)''',
  r'''CREATE TABLE message_logging_funnel_id(message_row_id INTEGER PRIMARY KEY,fs_funnel_id STRING,ps_funnel_id STRING)''',
  r'''CREATE TABLE message_quoted_text(message_row_id INTEGER PRIMARY KEY,thumbnail BLOB)''',
  r'''CREATE TABLE message_system_sibling_group_link_change(message_row_id INTEGER NOT NULL,subgroup_raw_jid TEXT NOT NULL,subgroup_subject TEXT NOT NULL,parent_group_jid_row_id INTEGER,PRIMARY KEY (message_row_id, subgroup_raw_jid))''',
  r'''CREATE TABLE message_system_number_change(message_row_id INTEGER PRIMARY KEY,old_jid_row_id INTEGER,new_jid_row_id INTEGER)''',
  r'''CREATE TABLE message_privacy_state(message_row_id INTEGER NOT NULL PRIMARY KEY,host_storage INTEGER,actual_actors INTEGER,privacy_mode_ts INTEGER NOT NULL,business_name TEXT)''',
  r'''CREATE TABLE message_system_ephemeral_setting_not_applied(message_row_id INTEGER PRIMARY KEY,setting_duration INTEGER)''',
  r'''CREATE TABLE call_unknown_caller(call_log_row_id INTEGER PRIMARY KEY)''',
  r'''CREATE TABLE message_media_interactive_annotation_vertex(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_media_interactive_annotation_row_id INTEGER,x REAL,y REAL,sort_order INTEGER)''',
  r'''CREATE TABLE message_media_interactive_annotation(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER,skip_confirmation INTEGER NOT NULL DEFAULT 0,location_latitude REAL,location_longitude REAL,location_name TEXT,newsletter_jid_row_id INTEGER,newsletter_server_message_id INTEGER,newsletter_name TEXT,newsletter_content_type INTEGER,newsletter_accessibility_text TEXT,sort_order INTEGER,child_message_row_id INTEGER,type INTEGER,fp_interactive_annotation BLOB,status_link_type INTEGER)''',
  r'''CREATE TABLE chat(_id INTEGER PRIMARY KEY AUTOINCREMENT,jid_row_id INTEGER UNIQUE,hidden INTEGER,subject TEXT,created_timestamp INTEGER,display_message_row_id INTEGER,last_message_row_id INTEGER,last_read_message_row_id INTEGER,last_read_receipt_sent_message_row_id INTEGER,last_important_message_row_id INTEGER,archived INTEGER,sort_timestamp INTEGER,mod_tag INTEGER,gen REAL,spam_detection INTEGER,unseen_earliest_message_received_time INTEGER,unseen_message_count INTEGER,unseen_missed_calls_count INTEGER,unseen_row_count INTEGER,plaintext_disabled INTEGER,vcard_ui_dismissed INTEGER,change_number_notified_message_row_id INTEGER,show_group_description INTEGER,ephemeral_expiration INTEGER,last_read_ephemeral_message_row_id INTEGER,ephemeral_setting_timestamp INTEGER,ephemeral_displayed_exemptions INTEGER,ephemeral_disappearing_messages_initiator INTEGER,unseen_important_message_count INTEGER NOT NULL DEFAULT 0,group_type INTEGER NOT NULL DEFAULT 0,last_message_reaction_row_id INTEGER,last_seen_message_reaction_row_id INTEGER,unseen_message_reaction_count INTEGER,unseen_comment_message_count INTEGER,growth_lock_level INTEGER,growth_lock_expiration_ts INTEGER,last_read_message_sort_id INTEGER,display_message_sort_id INTEGER,last_message_sort_id INTEGER,last_read_receipt_sent_message_sort_id INTEGER,has_new_community_admin_dialog_been_acknowledged INTEGER NOT NULL DEFAULT 0,history_sync_progress INTEGER,chat_lock INTEGER,chat_origin TEXT,participation_status INTEGER,account_jid_row_id INTEGER,chat_encryption_state INTEGER,group_member_count INTEGER,limited_sharing INTEGER,limited_sharing_setting_timestamp INTEGER, is_contact INTEGER, ephemeral_after_read_duration INTEGER, business_chat_state INTEGER, chat_props INTEGER)''',
  r'''CREATE TABLE message_system_block_contact(message_row_id INTEGER PRIMARY KEY,is_blocked INTEGER)''',
  r'''CREATE TABLE message_group_invite(message_row_id INTEGER PRIMARY KEY,group_jid_row_id INTEGER NOT NULL,admin_jid_row_id INTEGER NOT NULL,group_name TEXT,invite_code TEXT,expiration INTEGER,invite_time INTEGER,expired INTEGER,group_type INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE TABLE extended_media_data(row_id INTEGER PRIMARY KEY AUTOINCREMENT,type INTEGER NOT NULL,direct_path TEXT,file_path TEXT,file_hash TEXT,file_size INTEGER,media_key BLOB,media_key_timestamp INTEGER,enc_file_hash TEXT,width INTEGER,height INTEGER,media_caption TEXT,transferred INTEGER, preview_path TEXT, external_url TEXT, mime_type TEXT, display_type INTEGER)''',
  r'''CREATE TABLE user_device_info(user_jid_row_id INTEGER PRIMARY KEY,raw_id INTEGER NOT NULL,timestamp INTEGER NOT NULL,expected_timestamp INTEGER,expected_ts_last_device_job_ts INTEGER,expected_timestamp_update_ts INTEGER,account_encryption_type INTEGER)''',
  r'''CREATE TABLE message_sticker_pack_stickers(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER NOT NULL,file_name TEXT NOT NULL,is_animated INTEGER NOT NULL DEFAULT 0,emojis TEXT,accessibility_label TEXT,is_lottie INTEGER NOT NULL DEFAULT 0,mimetype TEXT)''',
  r'''CREATE TABLE message_revoked(message_row_id INTEGER PRIMARY KEY,revoked_key_id TEXT NOT NULL,admin_jid_row_id INTEGER,revoke_timestamp INTEGER)''',
  r'''CREATE TABLE message_call_log(message_row_id INTEGER PRIMARY KEY,call_log_row_id INTEGER)''',
  r'''CREATE TABLE message_vcard(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER,vcard TEXT)''',
  r'''CREATE TABLE message_quoted_ui_elements(message_row_id INTEGER NOT NULL PRIMARY KEY,element_type INTEGER,element_content TEXT)''',
  r'''CREATE TABLE message_poll(message_row_id INTEGER PRIMARY KEY,enc_key BLOB,selectable_options_count INTEGER,invalid_state INTEGER NOT NULL DEFAULT 0,poll_logging_id INTEGER NOT NULL DEFAULT 0,poll_type INTEGER,correct_option_id INTEGER,content_type INTEGER, hide_participant_names INTEGER, end_time INTEGER, allow_add_option INTEGER)''',
  r'''CREATE TABLE message_quoted_location(message_row_id INTEGER PRIMARY KEY,latitude REAL,longitude REAL,place_name TEXT,place_address TEXT,url TEXT,thumbnail BLOB)''',
  r'''CREATE TABLE played_self_receipt(message_row_id INTEGER PRIMARY KEY,to_jid_row_id INTEGER NOT NULL,participant_jid_row_id INTEGER,message_id TEXT NOT NULL)''',
  r'''CREATE TABLE message_system_photo_change(message_row_id INTEGER PRIMARY KEY,new_photo_id TEXT,old_photo BLOB,new_photo BLOB)''',
  r'''CREATE TABLE message_template(message_row_id INTEGER PRIMARY KEY,content_text_data TEXT NOT NULL,footer_text_data TEXT,template_id TEXT,csat_trigger_expiration_ts INTEGER,category TEXT,tag TEXT,mask_linked_devices INTEGER)''',
  r'''CREATE TABLE message_send_count(message_row_id INTEGER PRIMARY KEY,send_count INTEGER)''',
  r'''CREATE TABLE chat_ephemeral(chat_row_id INTEGER PRIMARY KEY,ephemeral_trigger INTEGER,ephemeral_initiated_by_me BOOLEAN, after_read_duration INTEGER)''',
  r'''CREATE TABLE message_rating(message_row_id INTEGER PRIMARY KEY,rating INTEGER NOT NULL)''',
  r'''CREATE TABLE message_ephemeral_setting(message_row_id INTEGER PRIMARY KEY,setting_duration INTEGER,setting_reason INTEGER,user_jid_row_id_csv TEXT,ephemeral_trigger INTEGER,ephemeral_initiated_by_me INTEGER, pre_setting_duration INTEGER, after_read_duration INTEGER)''',
  r'''CREATE TABLE frequent(_id INTEGER PRIMARY KEY AUTOINCREMENT,jid_row_id INTEGER NOT NULL,type INTEGER NOT NULL,message_count INTEGER NOT NULL, forward_count INTEGER, share_count INTEGER, cross_app_share_count INTEGER)''',
  r'''CREATE TABLE media_hash_thumbnail(media_hash TEXT PRIMARY KEY,thumbnail BLOB)''',
  r'''CREATE TABLE data_sharing_disclosure_metadata(message_row_id INTEGER PRIMARY KEY,show_mm_disclosure BOOLEAN)''',
  r'''CREATE TABLE message_span_indices(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER,start_index INTEGER,end_index INTEGER,span_type INTEGER)''',
  r'''CREATE TABLE ai_agentic_metadata(message_row_id INTEGER PRIMARY KEY,bot_progress_indicator_metadata BLOB)''',
  r'''CREATE TABLE community_chat(chat_row_id INTEGER PRIMARY KEY,last_activity_ts INTEGER,last_activity_seen_ts INTEGER,join_ts INTEGER,closed INTEGER NOT NULL DEFAULT 0, nesting_state INTEGER)''',
  r'''CREATE TABLE agent_devices(agent_id TEXT PRIMARY KEY NOT NULL,agent_name TEXT UNIQUE NOT NULL,device INTEGER,last_modified_time INTEGER,is_deleted BOOLEAN)''',
  r'''CREATE TABLE quick_reply_usage(_id INTEGER PRIMARY KEY AUTOINCREMENT,quick_reply_id TEXT NOT NULL,usage_date DATE,usage_count INTEGER)''',
  r'''CREATE TABLE composition_mention(_id INTEGER PRIMARY KEY AUTOINCREMENT,composition_row_id INTEGER NOT NULL,jid_row_id INTEGER NOT NULL, mention_type INTEGER)''',
  r'''CREATE TABLE message_quoted_vcard(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER,vcard TEXT)''',
  r'''CREATE TABLE message_invoice(message_row_id INTEGER PRIMARY KEY,wa_invoice_id TEXT NOT NULL,amount TEXT NOT NULL,note TEXT NOT NULL,token TEXT,sender_jid_row_id INTEGER,receiver_jid_row_id INTEGER,status INTEGER,status_ts INTEGER,creation_ts INTEGER,attachment_type INTEGER,attachment_mimetype TEXT,attachment_media_key BLOB,attachment_media_key_ts INTEGER,attachment_file_sha256 BLOB,attachment_file_enc_sha256 BLOB,attachment_direct_path TEXT,attachment_jpeg_thumbnail BLOB,metadata TEXT)''',
  r'''CREATE TABLE message_mentions(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER,jid_row_id INTEGER,display_name STRING, mention_type INTEGER)''',
  r'''CREATE TABLE message_system_biz_callback_disabled(message_row_id INTEGER PRIMARY KEY,callback_expiry_timestamp INTEGER,outgoing_failed_call_id TEXT)''',
  r'''CREATE TABLE message_system_username_change(message_row_id INTEGER PRIMARY KEY,user_jid INTEGER,old_username TEXT,new_username TEXT,display_name TEXT)''',
  r'''CREATE TABLE message_bcall_session(message_row_id INTEGER PRIMARY KEY,bcall_session_row_id INTEGER)''',
  r'''CREATE TABLE agent_chat_assignment(jid_row_id INTEGER PRIMARY KEY,account_jid_row_id INTEGER,agent_id TEXT NOT NULL,is_opened BOOLEAN)''',
  r'''CREATE TABLE message_fixed_content_placeholder(message_row_id INTEGER PRIMARY KEY,placeholder_type INTEGER NOT NULL)''',
  r'''CREATE TABLE user_device(_id INTEGER PRIMARY KEY AUTOINCREMENT,user_jid_row_id INTEGER,device_jid_row_id INTEGER,key_index INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE TABLE deleted_chat_job(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER NOT NULL,block_size INTEGER,singular_message_delete_rows_id TEXT,deleted_message_row_id INTEGER,deleted_starred_message_row_id INTEGER,deleted_messages_remove_files BOOLEAN,deleted_categories_message_row_id INTEGER,deleted_categories_starred_message_row_id INTEGER,deleted_categories_remove_files BOOLEAN,deleted_message_categories TEXT,delete_files_singular_delete BOOLEAN)''',
  r'''CREATE TABLE message_payment_invite(message_row_id INTEGER PRIMARY KEY,service INTEGER,expiration_timestamp INTEGER, incentive_eligible INTEGER, referral_id TEXT, invite_type INTEGER)''',
  r'''CREATE TABLE message_add_on(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER,from_me INTEGER,key_id TEXT NOT NULL,sender_jid_row_id INTEGER,parent_message_row_id INTEGER,timestamp INTEGER,status INTEGER,message_add_on_type INTEGER,received_timestamp INTEGER,expiry_duration_in_secs INTEGER,server_timestamp INTEGER,expiry_timestamp INTEGER,expiry_type INTEGER)''',
  r'''CREATE TABLE message_association(_id INTEGER PRIMARY KEY AUTOINCREMENT,child_message_row_id INTEGER NOT NULL,parent_message_row_id INTEGER NOT NULL,association_type INTEGER NOT NULL)''',
  r'''CREATE TABLE group_history_metadata(message_row_id INTEGER PRIMARY KEY NOT NULL,history_receivers TEXT NOT NULL,first_message_timestamp_seconds INTEGER NOT NULL,message_count INTEGER NOT NULL, non_history_receivers TEXT, oldest_message_timestamp_in_bundle_seconds INTEGER)''',
  r'''CREATE TABLE group_history_bundle(message_row_id INTEGER PRIMARY KEY NOT NULL,process_state INTEGER NOT NULL DEFAULT 0, send_state INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE TABLE message_question(message_row_id INTEGER PRIMARY KEY,response_count INTEGER DEFAULT 0, response_read_count INTEGER DEFAULT 0, is_enabled INTEGER DEFAULT 1)''',
  r'''CREATE TABLE message_system_detected_outcomes_labeled_chat(message_row_id INTEGER PRIMARY KEY,predefined_id INTEGER)''',
  r'''CREATE TABLE gap_enforcement_business_chat_thread_info_cache(business_chat_row_id INTEGER PRIMARY KEY NOT NULL,business_chat_is_mm_thread INTEGER, business_chat_thread_type INTEGER)''',
  r'''CREATE TABLE thread_id(_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,chat_row_id INTEGER NOT NULL,from_me INTEGER NOT NULL,key_id TEXT NOT NULL,sender_jid_row_id INTEGER NOT NULL DEFAULT 0,thread_type INTEGER NOT NULL DEFAULT 0, pin_timestamp INTEGER, deleted INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE TABLE thread_messages(_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,thread_id INTEGER NOT NULL,message_row_id INTEGER NOT NULL)''',
  r'''CREATE TABLE group_history_bundle_association(message_row_id INTEGER PRIMARY KEY NOT NULL,bundle_message_row_id INTEGER NOT NULL, message_sort_id INTEGER, bundle_sender_jid_row_id INTEGER, bundle_message_key_id TEXT, bundle_message_key_from_me BOOLEAN, bundle_message_key_chat_row_id INTEGER)''',
  r'''CREATE TABLE tee_message_info_table(message_row_id INTEGER PRIMARY KEY NOT NULL,message_interaction_type INTEGER,message_outgoing_status INTEGER,message_source INTEGER NOT NULL,message_replay_metadata BLOB)''',
  r'''CREATE TABLE reminder(_id INTEGER PRIMARY KEY AUTOINCREMENT,reminder_id TEXT NOT NULL,message_row_id INTEGER,call_log_row_id INTEGER,surface INTEGER NOT NULL,timestamp DATETIME NOT NULL,notified INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE TABLE status_attribution(_id INTEGER PRIMARY KEY AUTOINCREMENT,status_row_id INTEGER NOT NULL,type INTEGER NOT NULL,content BLOB)''',
  r'''CREATE TABLE message_add_on_status_question_answer(message_add_on_row_id INTEGER PRIMARY KEY,answer TEXT)''',
  r'''CREATE TABLE message_system_privacy(message_row_id INTEGER PRIMARY KEY,is_transition INTEGER,message_privacy_type INTEGER)''',
  r'''CREATE TABLE message_add_on_question_response(message_add_on_row_id INTEGER PRIMARY KEY,response TEXT)''',
  r'''CREATE TABLE question_reply_quoted_message(message_row_id INTEGER PRIMARY KEY,question_text TEXT,response_text TEXT,server_question_id INTEGER, question_message_type INTEGER)''',
  r'''CREATE TABLE integrity_chat_info(chat_row_id INTEGER PRIMARY KEY,is_reach_out INTEGER, is_eligible_for_link_friction_banner INTEGER)''',
  r'''CREATE TABLE frequent_forward_chat(chat_row_id INTEGER PRIMARY KEY,num_forward INTEGER,last_forward_timestamp INTEGER, last_scan INTEGER, num_image INTEGER, num_video INTEGER, num_gif INTEGER)''',
  r'''CREATE TABLE status_info_ranking_signals(chat_jid TEXT PRIMARY KEY NOT NULL,first_status_timestamp INTEGER NOT NULL DEFAULT 0,last_expired_status_timestamp INTEGER NOT NULL DEFAULT 0, cached_engagement_data BLOB, cached_engagement_timestamp INTEGER)''',
  r'''CREATE TABLE status_quoted_message(message_row_id INTEGER PRIMARY KEY,description_text TEXT NOT NULL,thumbnail BLOB,type INTEGER,original_status_key_id TEXT,original_status_is_from_me INTEGER,original_status_chat_id TEXT,original_status_sender_id TEXT,add_on_key_id TEXT,add_on_is_from_me INTEGER,add_on_chat_id TEXT,add_on_sender_id TEXT)''',
  r'''CREATE TABLE message_add_on_status_sticker_interaction(message_add_on_row_id INTEGER PRIMARY KEY,sticker_key TEXT,type INTEGER)''',
  r'''CREATE TABLE ai_thread_info(thread_id_row_id INTEGER PRIMARY KEY,title TEXT,creation_ts INTEGER NOT NULL,variant INTEGER NOT NULL DEFAULT 1,last_thread_messages_row_id INTEGER,last_message_timestamp INTEGER, title_source INTEGER, unseen_message_count INTEGER, origin_chat_row_id INTEGER, selected_mode INTEGER, selected_modes BLOB)''',
  r'''CREATE TABLE message_inline_video_metadata(message_row_id INTEGER PRIMARY KEY NOT NULL,video_content_url TEXT NOT NULL,is_muted INTEGER NOT NULL DEFAULT 0, caption TEXT)''',
  r'''CREATE TABLE payment_extended_metadata(message_row_id INTEGER PRIMARY KEY,platform TEXT,type INTEGER,message_params_json TEXT)''',
  r'''CREATE TABLE bot_message_sharing_info(message_row_id INTEGER PRIMARY KEY,message_id TEXT,bot_entry_point_origin INTEGER,forward_score INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE TABLE integrity_deleted_chat_message_count(id INTEGER PRIMARY KEY AUTOINCREMENT,lid TEXT NOT NULL DEFAULT '',messages_receive_date TEXT NOT NULL DEFAULT '',messages_count INTEGER NOT NULL DEFAULT 0, outgoing_messages_count INTEGER, messages_count_after_privacy_token INTEGER)''',
  r'''CREATE TABLE integrity_deleted_chat_metadata(id INTEGER PRIMARY KEY AUTOINCREMENT,lid TEXT NOT NULL DEFAULT '',chat_type INTEGER NOT NULL DEFAULT 1,is_first_reach_out INTEGER NOT NULL DEFAULT 0,chat_creation_timestamp INTEGER NOT NULL DEFAULT 0,last_incoming_message_timestamp INTEGER NOT NULL DEFAULT 0,lidHash TEXT NOT NULL DEFAULT '')''',
  r'''CREATE TABLE message_newsletter_follower_invite(message_row_id INTEGER PRIMARY KEY,newsletter_jid_row_id INTEGER NOT NULL,newsletter_name TEXT NOT NULL)''',
  r'''CREATE TABLE dynamic_audience_sources(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER NOT NULL,dynamic_audience_type INTEGER NOT NULL,dynamic_audience_id INTEGER NOT NULL)''',
  r'''CREATE TABLE broadcast_chat_details(chat_row_id INTEGER PRIMARY KEY NOT NULL,use_case INTEGER NOT NULL)''',
  r'''CREATE TABLE message_system_update_audience_linking(message_row_id INTEGER PRIMARY KEY,lists_to_remove_count INTEGER,lists_to_sync_count INTEGER)''',
  r'''CREATE TABLE message_quarantine(message_row_id INTEGER PRIMARY KEY,chat_row_id INTEGER,timestamp INTEGER NOT NULL,original_protobuf BLOB NOT NULL,serialized_stanza BLOB, protobuf_type INTEGER)''',
  r'''CREATE TABLE message_structure_analysis_result(message_row_id INTEGER PRIMARY KEY NOT NULL,message_field_json_array TEXT,submessage_field_json_array TEXT,button_value_json_array TEXT, cta_url_unique_count INTEGER, body_url_count INTEGER, body_url_unique_count INTEGER, url_unique_count INTEGER, decision_id TEXT, decision_sources TEXT)''',
  r'''CREATE TABLE recently_selected_search_table(recent_chat_row_id INTEGER PRIMARY KEY,search_timestamp INTEGER)''',
  r'''CREATE TABLE message_biz_context_info(message_row_id INTEGER PRIMARY KEY,weblink_render_config INTEGER, business_interaction_pills BLOB, preview_match_url TEXT)''',
  r'''CREATE TABLE tee_chat_request_table(message_row_id INTEGER PRIMARY KEY NOT NULL,chat_request_type TEXT NOT NULL, anchor_message_row_id INTEGER, node_token TEXT, extra_data BLOB)''',
  r'''CREATE TABLE message_system_side_chat_privacy(message_row_id INTEGER PRIMARY KEY,origin_chat_row_id INTEGER NOT NULL)''',
  r'''CREATE TABLE interactive_message_header_content(_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,message_row_id INTEGER NOT NULL,header_title TEXT,header_sub_title TEXT,header_thumbnail BLOB,document_url TEXT,document_direct_path TEXT,document_media_key BLOB,document_media_key_timestamp_ms INTEGER,document_media_hash TEXT,document_media_enc_hash TEXT,document_mime_type TEXT,document_file_name TEXT,document_file_path TEXT,document_file_length INTEGER)''',
  r'''CREATE TABLE interactive_message_sections(_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,message_row_id INTEGER NOT NULL,section_index INTEGER NOT NULL,section_title TEXT,section_highlight_label TEXT,item_index INTEGER NOT NULL,item_id TEXT,item_header TEXT,item_title TEXT,item_description TEXT)''',
  r'''CREATE TABLE interactive_message_bloks_widget(_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,message_row_id INTEGER NOT NULL,uuid TEXT,data TEXT,type TEXT, fallback TEXT)''',
  r'''CREATE TABLE status_privacy_custom_list(row_id INTEGER PRIMARY KEY AUTOINCREMENT,list_id TEXT NOT NULL,name TEXT,emoji TEXT,is_selected INTEGER NOT NULL DEFAULT 0,member_jids TEXT, source_group_jids TEXT, allow_list_selected INTEGER)''',
  r'''CREATE TABLE group_history_share_reporting_info(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER NOT NULL,stanza_id TEXT NOT NULL,reporting_token BLOB,reporting_token_version INTEGER,added_timestamp DATETIME NOT NULL,send_timestamp DATETIME,reporting_tag BLOB,is_send INTEGER, validation_policy TEXT)''',
  r'''CREATE TABLE feature_key_store(_id INTEGER PRIMARY KEY AUTOINCREMENT,key_id TEXT NOT NULL,key BLOB,key_type INTEGER NOT NULL,creation_timestamp INTEGER NOT NULL,expiry_timestamp INTEGER, key_jid TEXT NOT NULL DEFAULT '')''',
  r'''CREATE TABLE message_ai_media_collection(message_row_id INTEGER PRIMARY KEY,collection_id TEXT,expected_media_count INTEGER,has_global_caption INTEGER)''',
  r'''CREATE TABLE 'ai_thread_info_fts_content'(docid INTEGER PRIMARY KEY, 'c0search_content')''',
  r'''CREATE TABLE 'ai_thread_info_fts_segments'(blockid INTEGER PRIMARY KEY, block BLOB)''',
  r'''CREATE TABLE 'ai_thread_info_fts_segdir'(level INTEGER,idx INTEGER,start_block INTEGER,leaves_end_block INTEGER,end_block INTEGER,root BLOB,PRIMARY KEY(level, idx))''',
  r'''CREATE TABLE 'ai_thread_info_fts_docsize'(docid INTEGER PRIMARY KEY, size BLOB)''',
  r'''CREATE TABLE 'ai_thread_info_fts_stat'(id INTEGER PRIMARY KEY, value BLOB)''',
  r'''CREATE TABLE poll_vote_delivered_option(_id INTEGER PRIMARY KEY AUTOINCREMENT,parent_message_row_id INTEGER,message_poll_option_id INTEGER)''',
  r'''CREATE TABLE message_event_invite(message_row_id INTEGER PRIMARY KEY,event_id TEXT NOT NULL,event_title TEXT NOT NULL,start_time INTEGER,is_canceled INTEGER DEFAULT 0,caption TEXT, end_time INTEGER, call_link TEXT, cover_image_width INTEGER, cover_image_height INTEGER, cover_image_handle TEXT, location_name TEXT, last_updated_ts_usec INTEGER, is_updated INTEGER, status INTEGER)''',
  r'''CREATE TABLE poll_edit_snapshot(_id INTEGER PRIMARY KEY AUTOINCREMENT,parent_message_row_id INTEGER,previous_poll_name TEXT)''',
  r'''CREATE TABLE receipt_coex(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_row_id INTEGER NOT NULL,user_lid_row_id INTEGER NOT NULL,receipt_coex_timestamp INTEGER)''',
  r'''CREATE TABLE group_root_key_mapping(_id INTEGER PRIMARY KEY AUTOINCREMENT,group_jid_row_id INTEGER NOT NULL,key_id TEXT NOT NULL,is_current INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE TABLE message_add_on_receipt_coex(_id INTEGER PRIMARY KEY AUTOINCREMENT,message_add_on_row_id INTEGER NOT NULL,user_lid_row_id INTEGER NOT NULL,receipt_coex_timestamp INTEGER)''',
  r'''CREATE TABLE message_split_payment(message_row_id INTEGER NOT NULL,split_id TEXT PRIMARY KEY,total_amount_value INTEGER NOT NULL DEFAULT 0,total_amount_offset INTEGER NOT NULL DEFAULT 1,currency_code TEXT NOT NULL DEFAULT 'INR',description TEXT,requester_jid_row_id INTEGER,created_at_ms INTEGER, chat_jid_row_id INTEGER)''',
  r'''CREATE TABLE message_split_payment_participant(split_id TEXT NOT NULL,jid_row_id INTEGER NOT NULL,share_amount_value INTEGER NOT NULL DEFAULT 0,share_amount_offset INTEGER NOT NULL DEFAULT 1,currency_code TEXT NOT NULL DEFAULT 'INR',status_value INTEGER NOT NULL DEFAULT 0, transaction_id TEXT,PRIMARY KEY (split_id, jid_row_id))''',
  r'''CREATE TABLE auth_agent_chat_metadata(chat_row_id INTEGER PRIMARY KEY,parent_company_name TEXT,oba_phone_number TEXT)''',
  r'''CREATE TABLE message_payment_reminder(message_row_id INTEGER PRIMARY KEY NOT NULL,reminder_id TEXT NOT NULL,instance_id TEXT NOT NULL,description TEXT,frequency TEXT,status TEXT,payee_vpa TEXT,payee_jid_row_id INTEGER,payer_jid_row_id INTEGER,amount_value INTEGER,amount_offset INTEGER,amount_currency_code TEXT)''',
  r'''CREATE TABLE message_quoted_event_invite(message_row_id INTEGER PRIMARY KEY,event_id TEXT NOT NULL,event_title TEXT NOT NULL,start_time INTEGER,end_time INTEGER,is_canceled INTEGER DEFAULT 0,caption TEXT,call_link TEXT, cover_image_handle TEXT, location_name TEXT, last_updated_ts_usec INTEGER, is_updated INTEGER, status INTEGER)''',
  r'''CREATE TABLE newsletter_jarvis_config(chat_row_id INTEGER PRIMARY KEY,config_json TEXT NOT NULL)''',
  r'''CREATE TABLE aea_chat_state(chat_row_id INTEGER PRIMARY KEY NOT NULL,cooldown_state INTEGER NOT NULL,cooldown_started_at INTEGER NOT NULL)''',
  r'''CREATE TABLE newsletter_media_clear(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER NOT NULL,media_type INTEGER NOT NULL,cutoff_sort_id INTEGER NOT NULL)''',
  r'''CREATE TABLE poll_name_hash_history(_id INTEGER PRIMARY KEY AUTOINCREMENT,poll_message_row_id INTEGER NOT NULL,edit_stanza_id TEXT NOT NULL,poll_name_hash BLOB NOT NULL)''',
  r'''CREATE TABLE newsletter_pinned_message(message_row_id INTEGER PRIMARY KEY,chat_row_id INTEGER NOT NULL,server_message_id INTEGER NOT NULL,expiry_ts_seconds INTEGER NOT NULL,pin_timestamp_ms INTEGER NOT NULL)''',
  r'''CREATE TABLE poll_vote_pending(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER NOT NULL,from_me INTEGER NOT NULL,key_id TEXT NOT NULL,sender_jid_row_id INTEGER NOT NULL,message_timestamp_ms INTEGER NOT NULL,poll_message_row_id INTEGER NOT NULL,dependency_type INTEGER NOT NULL,dependency_id TEXT NOT NULL,metadata_edit_stanza_id TEXT,metadata_poll_name_hash BLOB,selected_option_hashes BLOB NOT NULL,sender_timestamp_ms INTEGER NOT NULL,unread INTEGER NOT NULL,created_timestamp_ms INTEGER NOT NULL)''',
  r'''CREATE TABLE label_sublist(_id INTEGER PRIMARY KEY AUTOINCREMENT,predefined_id INTEGER NOT NULL,jid_row_id INTEGER NOT NULL,sub_list_id INTEGER NOT NULL)''',
  r'''CREATE TABLE message_music(message_row_id INTEGER PRIMARY KEY NOT NULL,song_uri TEXT,artwork_uri TEXT,style_raw_value INTEGER NOT NULL)''',
  r'''CREATE TABLE newsletter_admin_profile(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER NOT NULL,admin_profile_id TEXT NOT NULL,name TEXT,picture_id TEXT,picture_direct_path TEXT,timestamp INTEGER NOT NULL)''',
  r'''CREATE TABLE embeddings_deletion_log(_id INTEGER PRIMARY KEY,message_row_id INTEGER NOT NULL,sort_id INTEGER NOT NULL)''',
  r'''CREATE TABLE label_schedule_time(_id INTEGER PRIMARY KEY AUTOINCREMENT,label_id INTEGER NOT NULL,days INTEGER,start_minutes INTEGER,end_minutes INTEGER)''',
  r'''CREATE TABLE message_acp2_setting(message_row_id INTEGER PRIMARY KEY,enabled INTEGER,trigger INTEGER,setting_timestamp INTEGER)''',
  r'''CREATE TABLE message_appointment(message_row_id INTEGER PRIMARY KEY NOT NULL,appointment_id TEXT NOT NULL,status INTEGER NOT NULL,format INTEGER,start_time_secs INTEGER,end_time_secs INTEGER,call_link TEXT,client_note TEXT,canceled_by_business INTEGER)''',
  r'''CREATE TABLE newsletter_interaction(_id INTEGER PRIMARY KEY AUTOINCREMENT,type TEXT NOT NULL,newsletter_jid_row_id INTEGER NOT NULL,timestamp_ms INTEGER NOT NULL)''',
  r'''CREATE TABLE newsletter_scheduled_message(message_row_id INTEGER PRIMARY KEY,chat_row_id INTEGER NOT NULL,scheduled_server_id INTEGER,publish_at_ms INTEGER NOT NULL,terminal_reason TEXT)''',
  r'''CREATE TABLE ai_scheduled_task_info(_id INTEGER PRIMARY KEY,task_id TEXT NOT NULL,message_row_id INTEGER NOT NULL,message_timestamp INTEGER NOT NULL)''',
  r'''CREATE TABLE chat_encryption_classification(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER NOT NULL,classification_type INTEGER NOT NULL,contributing_jid_row_id INTEGER NOT NULL)''',
  r'''CREATE TABLE sticker_audio_media(message_row_id INTEGER PRIMARY KEY,url TEXT,direct_path TEXT,media_key BLOB,media_key_timestamp INTEGER,media_key_domain INTEGER,e2ee_media_key BLOB,file_sha256 BLOB,file_enc_sha256 BLOB,file_length INTEGER,duration_seconds INTEGER,mimetype TEXT,waveform BLOB,streaming_sidecar BLOB,file_path TEXT,transferred INTEGER DEFAULT 0)''',
  r'''CREATE TABLE message_conditional_reveal(message_row_id INTEGER PRIMARY KEY,proto_data BLOB,stanza_data BLOB,key_id TEXT,key_jid TEXT,conditional_reveal_type INTEGER,reporting_token_info BLOB,chat_row_id INTEGER,from_me INTEGER,scheduled_time INTEGER)''',
  r'''CREATE TABLE poll_original_option(_id INTEGER PRIMARY KEY AUTOINCREMENT,poll_message_row_id INTEGER NOT NULL,option_index INTEGER NOT NULL,option_name TEXT NOT NULL,option_hash TEXT)''',
  r'''CREATE TABLE message_chat_theme_setting(message_row_id INTEGER PRIMARY KEY NOT NULL,setting_timestamp_ms INTEGER NOT NULL,setter_jid_row_id INTEGER NOT NULL DEFAULT 0,clear_theme INTEGER,color_scheme_id TEXT,wallpaper_type INTEGER NOT NULL,wallpaper_asset_id TEXT,dim_level REAL,is_doodle_enabled INTEGER,background_light_argb INTEGER,background_dark_argb INTEGER,doodle_light_argb INTEGER,doodle_dark_argb INTEGER,known_at_receipt INTEGER NOT NULL DEFAULT 0,timestamp_accepted INTEGER NOT NULL DEFAULT 0,applied INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE TABLE private_ai_message_epoch(message_row_id INTEGER PRIMARY KEY,epoch_anon_id INTEGER NOT NULL)''',
  r'''CREATE TABLE private_ai_sync_mutation_table(_id INTEGER PRIMARY KEY AUTOINCREMENT,scope_id INTEGER NOT NULL,message_row_id INTEGER NOT NULL,operation INTEGER NOT NULL,retry_count INTEGER NOT NULL DEFAULT 0,key_remote_jid_row_id INTEGER,key_id TEXT,key_from_me INTEGER,key_sender_jid_row_id INTEGER,thread_key TEXT)''',
  r'''CREATE TABLE private_ai_sync_scope_table(_id INTEGER PRIMARY KEY AUTOINCREMENT,chat_row_id INTEGER NOT NULL,thread_id INTEGER NOT NULL DEFAULT 0,enable_boundary_message_row_id INTEGER NOT NULL,retroactive_floor_message_row_id INTEGER NOT NULL,retroactive_cursor_message_row_id INTEGER NOT NULL,realtime_cursor_message_row_id INTEGER NOT NULL,retroactive_complete INTEGER NOT NULL DEFAULT 0)''',
  r'''CREATE VIEW available_message_view AS
            SELECT
              
            message._id AS _id,
            message.sort_id AS sort_id,
            message.chat_row_id AS chat_row_id,
            from_me,
            key_id,
            sender_jid_row_id,
            status,
            broadcast,
            recipient_count,
            participant_hash,
            origination_flags,
            origin,
            timestamp,
            received_timestamp,
            receipt_server_timestamp,
            message_type,
            text_data,
            translated_text,
            starred,
            lookup_tables,
            message_add_on_flags,
            view_mode
        ,
              expire_timestamp,
              keep_in_chat,
              view_replies_thread_id,
              server_sts
            FROM
              message
              LEFT JOIN deleted_chat_job AS job
              ON job.chat_row_id = message.chat_row_id
              LEFT JOIN message_ephemeral AS message_ephemeral
              ON message._id = message_ephemeral.message_row_id
            WHERE
              IFNULL(NOT(
                
            (
                IFNULL(message.starred, 0) = 0
                AND
                message.sort_id <=
                    IFNULL(job.deleted_message_row_id, -9223372036854775808)
            )
        
                OR
                
            (
                IFNULL(message.starred, 0) = 1
                AND
                message.sort_id <=
                    IFNULL(job.deleted_starred_message_row_id, -9223372036854775808)
            )
        
                OR
                
            (
                (job.deleted_message_categories IS NOT NULL)
                AND
                (job.deleted_message_categories 
                    LIKE '%"' || message.message_type || '"%')
                AND
                (   
                    
            (
                IFNULL(message.starred, 0) = 0
                AND
                message.sort_id <= 
                    IFNULL(job.deleted_categories_message_row_id, -9223372036854775808)
            )
        
                    OR
                    
            (
                IFNULL(message.starred, 0) = 1
                AND
                message.sort_id <=
                    IFNULL(job.deleted_categories_starred_message_row_id, -9223372036854775808)
            )
        
                )
            )                    
        
                OR
                
            (
                (job.singular_message_delete_rows_id IS NOT NULL)
                AND
                (job.singular_message_delete_rows_id
                    LIKE '%"' || message._id || '"%')
            )
        
        ), 0)''',
  r'''CREATE VIEW deleted_messages_view AS
          SELECT
            
            message._id AS _id,
            message.sort_id AS sort_id,
            message.chat_row_id AS chat_row_id,
            from_me,
            key_id,
            sender_jid_row_id,
            status,
            broadcast,
            recipient_count,
            participant_hash,
            origination_flags,
            origin,
            timestamp,
            received_timestamp,
            receipt_server_timestamp,
            message_type,
            text_data,
            translated_text,
            starred,
            lookup_tables,
            message_add_on_flags,
            view_mode
        ,
            (
            (
                
            (
                (job.singular_message_delete_rows_id 
                    LIKE '%"' || message._id || '"%')
                AND
                (job.delete_files_singular_delete == 1)
            )
        
                OR
                (
                    (job.deleted_messages_remove_files == 1)
                    AND
                    (
                        
            (
                IFNULL(message.starred, 0) = 0
                AND
                message.sort_id <=
                    IFNULL(job.deleted_message_row_id, -9223372036854775808)
            )
        
                        OR
                        
            (
                IFNULL(message.starred, 0) = 1
                AND
                message.sort_id <=
                    IFNULL(job.deleted_starred_message_row_id, -9223372036854775808)
            )
        
                    )
                )
                OR
                (
                    (job.deleted_categories_remove_files == 1)
                    AND
                    
            (
                (job.deleted_message_categories IS NOT NULL)
                AND
                (job.deleted_message_categories 
                    LIKE '%"' || message.message_type || '"%')
                AND
                (   
                    
            (
                IFNULL(message.starred, 0) = 0
                AND
                message.sort_id <= 
                    IFNULL(job.deleted_categories_message_row_id, -9223372036854775808)
            )
        
                    OR
                    
            (
                IFNULL(message.starred, 0) = 1
                AND
                message.sort_id <=
                    IFNULL(job.deleted_categories_starred_message_row_id, -9223372036854775808)
            )
        
                )
            )                    
        
                )
          )
        ) AS remove_files,
            view_replies_thread_id,
            server_sts
          FROM
            deleted_chat_job AS job
            JOIN message AS message
              ON job.chat_row_id = message.chat_row_id
          WHERE
            IFNULL(
            (
                (
                    
                
            (
                IFNULL(message.starred, 0) = 0
                AND
                message.sort_id <=
                    IFNULL(job.deleted_message_row_id, -9223372036854775808)
            )
        
                OR
                
            (
                IFNULL(message.starred, 0) = 1
                AND
                message.sort_id <=
                    IFNULL(job.deleted_starred_message_row_id, -9223372036854775808)
            )
        
                OR
                
            (
                (job.deleted_message_categories IS NOT NULL)
                AND
                (job.deleted_message_categories 
                    LIKE '%"' || message.message_type || '"%')
                AND
                (   
                    
            (
                IFNULL(message.starred, 0) = 0
                AND
                message.sort_id <= 
                    IFNULL(job.deleted_categories_message_row_id, -9223372036854775808)
            )
        
                    OR
                    
            (
                IFNULL(message.starred, 0) = 1
                AND
                message.sort_id <=
                    IFNULL(job.deleted_categories_starred_message_row_id, -9223372036854775808)
            )
        
                )
            )                    
        
                OR
                
            (
                (job.singular_message_delete_rows_id IS NOT NULL)
                AND
                (job.singular_message_delete_rows_id
                    LIKE '%"' || message._id || '"%')
            )
        
        
                )
                AND
                
            (
                (IFNULL(message.origination_flags, 0) & 1099511627776) = 0
            )
        
          )
        , 0)
          ORDER BY message._id''',
  r'''CREATE VIEW deleted_messages_ids_view AS
          SELECT
            message._id,
            message.sort_id,
            message.chat_row_id,
            message.message_type
          FROM 
            deleted_chat_job AS job
            JOIN message AS message
              ON job.chat_row_id = message.chat_row_id
          WHERE
            IFNULL(
            (
                (
                    
                
            (
                IFNULL(message.starred, 0) = 0
                AND
                message.sort_id <=
                    IFNULL(job.deleted_message_row_id, -9223372036854775808)
            )
        
                OR
                
            (
                IFNULL(message.starred, 0) = 1
                AND
                message.sort_id <=
                    IFNULL(job.deleted_starred_message_row_id, -9223372036854775808)
            )
        
                OR
                
            (
                (job.deleted_message_categories IS NOT NULL)
                AND
                (job.deleted_message_categories 
                    LIKE '%"' || message.message_type || '"%')
                AND
                (   
                    
            (
                IFNULL(message.starred, 0) = 0
                AND
                message.sort_id <= 
                    IFNULL(job.deleted_categories_message_row_id, -9223372036854775808)
            )
        
                    OR
                    
            (
                IFNULL(message.starred, 0) = 1
                AND
                message.sort_id <=
                    IFNULL(job.deleted_categories_starred_message_row_id, -9223372036854775808)
            )
        
                )
            )                    
        
                OR
                
            (
                (job.singular_message_delete_rows_id IS NOT NULL)
                AND
                (job.singular_message_delete_rows_id
                    LIKE '%"' || message._id || '"%')
            )
        
        
                )
                AND
                
            (
                (IFNULL(message.origination_flags, 0) & 1099511627776) = 0
            )
        
          )
        , 0)''',
  r'''CREATE VIEW chat_view AS
            SELECT
                
                chat._id AS _id,
                chat.hidden AS hidden,
                chat.subject AS subject,
                chat.created_timestamp AS created_timestamp,
                chat.last_message_row_id AS last_message_row_id,
                chat.display_message_row_id AS display_message_row_id,
                chat.last_read_message_row_id AS last_read_message_row_id,
                chat.last_read_receipt_sent_message_row_id AS last_read_receipt_sent_message_row_id,
                chat.last_important_message_row_id AS last_important_message_row_id,
                chat.archived AS archived,
                chat.sort_timestamp AS sort_timestamp,
                chat.mod_tag AS mod_tag,
                chat.gen AS gen,
                chat.spam_detection AS spam_detection,
                chat.unseen_earliest_message_received_time AS unseen_earliest_message_received_time,
                chat.unseen_message_count AS unseen_message_count,
                chat.unseen_missed_calls_count AS unseen_missed_calls_count,
                chat.unseen_row_count AS unseen_row_count,
                chat.unseen_message_reaction_count AS unseen_message_reaction_count,
                chat.unseen_comment_message_count AS unseen_comment_message_count,
                chat.last_message_reaction_row_id AS last_message_reaction_row_id,
                chat.last_seen_message_reaction_row_id AS last_seen_message_reaction_row_id,
                chat.plaintext_disabled AS plaintext_disabled,
                chat.vcard_ui_dismissed AS vcard_ui_dismissed,
                chat.change_number_notified_message_row_id AS change_number_notified_message_row_id,
                chat.show_group_description AS show_group_description,
                chat.ephemeral_expiration AS ephemeral_expiration,
                chat.ephemeral_setting_timestamp AS ephemeral_setting_timestamp,
                chat.ephemeral_displayed_exemptions AS ephemeral_displayed_exemptions,
                chat.ephemeral_disappearing_messages_initiator AS ephemeral_disappearing_messages_initiator,
                chat.unseen_important_message_count AS unseen_important_message_count,
                chat.group_type AS group_type,
                chat.growth_lock_level AS growth_lock_level,
                chat.growth_lock_expiration_ts AS growth_lock_expiration_ts,
                chat.last_read_message_sort_id AS last_read_message_sort_id,
                chat.display_message_sort_id AS display_message_sort_id,
                chat.last_message_sort_id AS last_message_sort_id,
                chat.last_read_receipt_sent_message_sort_id AS last_read_receipt_sent_message_sort_id,
                chat.has_new_community_admin_dialog_been_acknowledged AS has_new_community_admin_dialog_been_acknowledged,
                chat.history_sync_progress AS history_sync_progress,
                chat.chat_lock AS chat_lock,
                chat.chat_origin AS chat_origin,
                chat.participation_status AS participation_status,
                chat.chat_encryption_state AS chat_encryption_state,
                chat.group_member_count AS group_member_count,
                chat.limited_sharing AS limited_sharing,
                chat.limited_sharing_setting_timestamp AS limited_sharing_setting_timestamp,
                chat.is_contact AS is_contact,
                chat.ephemeral_after_read_duration AS ephemeral_after_read_duration,
                chat.business_chat_state AS business_chat_state,
                chat.chat_props AS chat_props
        ,
                CAST(
                  COALESCE(
                    chat.account_jid_row_id,
                    chat.jid_row_id
                  ) AS INTEGER) AS jid_row_id,
                chat.jid_row_id AS original_jid_row_id
            FROM chat AS chat''',
  r'''CREATE VIEW ws_messages as SELECT DISTINCT message._id , jid.raw_string as key_remote_jid, from_me as key_from_me, key_id , status ,0 as needs_push , text_data as data, timestamp , message_media.message_url as media_url, message_media.mime_type as media_mime_type,message_type as media_wa_type , message_media.file_length as media_size, message_media.media_name as media_name, NULL as media_caption, message_media.file_hash as media_hash,message_media.media_duration , origin , message_location.latitude , message_location.longitude , message_media.file_path as thumb_image ,jid_sender.raw_string as remote_resource, received_timestamp , -1 as send_timestamp,receipt_server_timestamp , -1 as receipt_device_timestamp ,- 1 as read_device_timestamp, NULL as played_device_timestamp, NULL as raw_data,recipient_count , participant_hash , starred , 0 as quoted_row_id,NULL as mentioned_jids, NULL as multicast_id , NULL as edit_version, message_media.enc_file_hash ,NULL as payment_transaction_id, NULL as forwarded,NULL as preview_type, NULL as send_count, starred FROM message left join chat on chat._id == message.chat_row_id left join jid on chat.jid_row_id == jid._id left join jid as jid_sender on jid_sender._id == message.sender_jid_row_id left join message_media on message_media.message_row_id == message._id left join message_location on message_location.message_row_id == message._id''',
];

/// Full-text-search virtual tables: (name, `CREATE VIRTUAL TABLE …`).
const waMsgstoreVirtualTables = <(String, String)>[
  (
    r'''ai_thread_info_fts''',
    r'''CREATE VIRTUAL TABLE ai_thread_info_fts USING FTS4 (
            search_content
          )''',
  ),
];
