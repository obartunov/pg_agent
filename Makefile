EXTENSION = pg_agent
DATA = pg_agent--1.0.sql
REGRESS = 001_smoke

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
