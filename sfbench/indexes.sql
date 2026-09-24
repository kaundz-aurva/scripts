-- Built after the bulk load (much faster than maintaining them during COPY). Same set as sfbench.
ALTER TABLE sensitive_fields ADD CONSTRAINT sensitive_fields_pkey PRIMARY KEY (id);
ALTER TABLE sensitivefield_tags ADD CONSTRAINT sensitivefield_tags_pkey PRIMARY KEY (sensitive_field_id, tag_id);
ALTER TABLE datasources ADD CONSTRAINT datasources_pkey PRIMARY KEY (id);

CREATE INDEX idx_sensitive_fields_datasource_identifier ON sensitive_fields (datasource_identifier);
CREATE INDEX idx_sensitive_fields_deleted_at ON sensitive_fields (deleted_at);
CREATE INDEX idx_sensitive_fields_dirty ON sensitive_fields (dirty);
CREATE INDEX idx_sensitive_fields_field_name ON sensitive_fields (field_name);
CREATE INDEX idx_sensitive_fields_scan_id ON sensitive_fields (scan_id);
CREATE INDEX idx_sensitive_fields_skip_reason ON sensitive_fields (skip_reason);
CREATE INDEX idx_sensitive_fields_status ON sensitive_fields (status);
CREATE INDEX idx_sf_ds_scan_id_live ON sensitive_fields (datasource_identifier, scan_id, id) WHERE deleted_at IS NULL AND is_archived = false;
CREATE INDEX idx_sf_ds_status_id_live ON sensitive_fields (datasource_identifier, status, id) WHERE deleted_at IS NULL AND is_archived = false;

CREATE INDEX idx_controller_uuid ON datasources (controller_uuid);
CREATE INDEX idx_datasources_arn ON datasources (arn);
CREATE INDEX idx_datasources_country ON datasources (country);
CREATE INDEX idx_datasources_health_status ON datasources (health_status);
CREATE INDEX idx_datasources_is_audit_log_monitoring_enabled ON datasources (is_audit_log_monitoring_enabled);
CREATE INDEX idx_datasources_name ON datasources (name);
CREATE INDEX idx_datasources_threat_level ON datasources (threat_level);
CREATE INDEX idx_datasources_sensitive_state ON datasources (sensitive_state);
CREATE INDEX idx_exp_status_proxy ON datasources (expected_status);
CREATE INDEX idx_ip ON datasources (ip_address);
CREATE INDEX idx_provider ON datasources (provider);
CREATE INDEX idx_scan_status ON datasources (scan_status);
CREATE INDEX idx_status_proxy ON datasources (proxy_port, status);
CREATE INDEX idx_type_creation_source_service_type ON datasources (creation_source, type, service_type);
CREATE UNIQUE INDEX udx_host_port ON datasources (port, host);
