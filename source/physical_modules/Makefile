# Thin convenience wrapper over scripts/. All real logic lives in scripts/ so
# they remain usable standalone. Select the target module and overrides via env:
#   make build MODULE=module_1
#   make upload PORT=/dev/cu.usbserial-1240
#   make monitor BAUD=115200

COMMS_SRC  := lib/comms/src
MATRIX_SRC := lib/matrix/src
BUS_SRC    := lib/bus/src
IO_SRC     := lib/io/src

.PHONY: check build test upload monitor list flash clean

check:   ## Compile-only sanity check (MODULE=module_1)
	./scripts/check.sh

build:   ## Build a module into build/<module>/ (MODULE=module_1)
	./scripts/build.sh

upload:  ## Compile + flash a module (MODULE=, PORT=)
	./scripts/upload.sh

monitor: ## Open the serial monitor (PORT=, BAUD=, Ctrl-C to quit)
	./scripts/monitor.sh

list:    ## List connected boards / serial ports
	./scripts/list.sh

flash: upload monitor ## Upload then immediately open the monitor

test:    ## Build and run host unit tests for the shared libraries
	@mkdir -p build
	c++ -std=c++17 -Wall -Wextra -I$(COMMS_SRC) test/test_framing.cpp \
		$(COMMS_SRC)/cobs.cpp $(COMMS_SRC)/framing.cpp $(COMMS_SRC)/frame_reader.cpp \
		-o build/test_framing
	c++ -std=c++17 -Wall -Wextra -I$(MATRIX_SRC) -I$(BUS_SRC) -Itest test/test_matrix.cpp \
		$(BUS_SRC)/bit_view.cpp $(MATRIX_SRC)/key_matrix.cpp $(MATRIX_SRC)/led_matrix.cpp \
		-o build/test_matrix
	c++ -std=c++17 -Wall -Wextra -I$(IO_SRC) -I$(BUS_SRC) -Itest test/test_io.cpp \
		$(IO_SRC)/analog_axis.cpp $(IO_SRC)/analog_edges.cpp \
		$(IO_SRC)/quadrature_encoder.cpp \
		$(IO_SRC)/button_bank.cpp $(IO_SRC)/key_reporter.cpp \
		$(IO_SRC)/pulse_activity.cpp \
		$(IO_SRC)/nfc_session.cpp $(IO_SRC)/ndef_text.cpp \
		-o build/test_io
	c++ -std=c++17 -Wall -Wextra -I$(MATRIX_SRC) -I$(IO_SRC) -I$(BUS_SRC) -Itest \
		test/test_module_7.cpp \
		$(BUS_SRC)/bit_view.cpp $(MATRIX_SRC)/key_matrix.cpp \
		$(MATRIX_SRC)/key_snapshot.cpp \
		$(IO_SRC)/key_reporter.cpp $(IO_SRC)/key_panel.cpp \
		-o build/test_module_7
	c++ -std=c++17 -Wall -Wextra -Imodules/module_2_demo/src \
		test/test_module_2_demo.cpp -o build/test_module_2_demo
	@./build/test_framing
	@./build/test_matrix
	@./build/test_io
	@./build/test_module_7
	@./build/test_module_2_demo

clean:   ## Remove local build artifacts
	rm -rf build
