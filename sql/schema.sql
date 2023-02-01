CREATE TABLE message (
    created TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL,
    id VARCHAR NOT NULL,
    int_id CHAR(16) NOT NULL,
    str VARCHAR NOT NULL,
    status BOOL,
    CONSTRAINT message_id_pk PRIMARY KEY(id)
);
CREATE INDEX message_created_idx ON message (created);
CREATE INDEX message_int_id_idx ON message (int_id);

CREATE TABLE log (
    created TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL,
    int_id CHAR(16) NOT NULL,
    str VARCHAR,
    address VARCHAR
);
CREATE INDEX log_address_idx ON log USING hash (address);
