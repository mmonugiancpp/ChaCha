
/*
    input         clock,
                  reset,
    input  [31:0] io_key_0,
                  io_key_1,
                  io_key_2,
                  io_key_3,
                  io_key_4,
                  io_key_5,
                  io_key_6,
                  io_key_7,
                  io_nonce_0,
                  io_nonce_1,
                  io_nonce_2,
                  io_position,
    input         io_start,
    input  [7:0]  io_plaintext,
    input         io_plain_valid,
    output        io_plain_ready,
    output [7:0]  io_cyphertext,
    output        io_cypher_valid,
    input         io_cypher_ready
*/

module MemoryManager(
    input wire        i_Rst_L,    // Reset, active low
    input wire        i_Clk,      // Clock

    // Control/Data Signals flowing between SPI Slave and this module
    input wire        o_RX_DV,    // Data Valid pulse (1 clock cycle)
    input wire [7:0]  o_RX_Byte,  // Byte received on MOSI
    output            i_TX_DV,    // Data Valid pulse to register i_TX_Byte
    output  [7:0]     i_TX_Byte,  // Byte to serialize to MISO.

    // outputs flowing over to the encryption module
    output wire [31:0]  io_key_0,
                        io_key_1,
                        io_key_2,
                        io_key_3,
                        io_key_4,
                        io_key_5,
                        io_key_6,
                        io_key_7,
                        io_nonce_0,
                        io_nonce_1,
                        io_nonce_2,
                        io_position,
    output reg          start
);

reg [7:0] keys [31:0]; // ordered smallest up, keys[0] is the lower 8 bits of io_key_0
reg [7:0] nonces [11:0]; // ordered likewise, nonces[0] is the lower 8 bits of io_nonce_0
reg [7:0] pos [3:0];
reg should_write; // this wire is an enable signal for writing into memory - high to enable

localparam IDLE = 3'b000;
localparam WRITE_KEY = 3'b001;
localparam WRITE_NONCE = 3'b010;
localparam WRITE_POS = 3'b011;
localparam READ_KEY = 3'b100;
localparam READ_NONCE = 3'b101;
localparam READ_POS = 3'b110;
localparam START = 3'b111;


reg [2:0] curr_state;
reg [2:0] next_state;

reg [4:0] counter;
reg [4:0] next_counter;


// sequential logic for keys, nonces, and pos
integer i;
    always @(posedge i_Clk or negedge i_Rst_L) begin
    if (~i_Rst_L) begin // zero all registers on reset
        for (i = 0; i < 32; i = i + 1) begin
            keys[i] <= 8'd0;
        end
        for (i = 0; i < 12; i = i + 1) begin
            nonces[i] <= 8'd0;
        end
        for (i = 0; i < 4; i = i + 1) begin
            pos[i] <= 8'd0;
        end
    end 
    else begin
        if(curr_state == WRITE_KEY && should_write == 1'b1) begin
            keys[counter] <= o_RX_Byte;
        end
        if(curr_state == WRITE_NONCE && should_write == 1'b1) begin
            nonces[counter] <= o_RX_Byte;
        end
        if(curr_state == WRITE_POS && should_write == 1'b1) begin
            pos[counter] <= o_RX_Byte;
        end
    end
end

// sequential logic for state machine
    always @(posedge i_Clk or negedge i_Rst_L) begin
    if(~i_Rst_L) begin
        counter <= 5'b00000;
        curr_state <= IDLE;
    end
    else begin
        counter <= next_counter;
        curr_state <= next_state;
    end
end

// combinational logic
always @(*) begin
    case (curr_state)
        IDLE : begin        // when we are idling
            next_state = IDLE;
            next_counter = 5'b00000;
            start = 1'b0;
            should_write = 1'b0;
            if(o_RX_DV) begin // and there is a valid byte to read
                case (o_RX_Byte)    // we go to the state determined by value of read byte
                    8'd1: next_state = WRITE_KEY;
                    8'd2: next_state = WRITE_NONCE;
                    8'd3: next_state = WRITE_POS;
                    8'd4: next_state = READ_KEY;
                    8'd5: next_state = READ_NONCE;
                    8'd6: next_state = READ_POS;
                    8'd7: next_state = START;
                    default: next_state = IDLE;
                endcase
            end
        end
        WRITE_KEY : begin // we are writing the keys
            next_state = WRITE_KEY;
            next_counter = counter;
            start = 1'b0;
            should_write = 1'b0;
            if(o_RX_DV) begin // there is a valid byte to read
                should_write = 1'b1;
                if(counter == 5'd31) begin // check counter value
                    next_counter = 5'd0; // zero counter if end of array
                    next_state = IDLE; // and go to idle
                end
                else begin
                    // we increment the counter otherwise
                    next_counter = counter + 5'd1;
                end
            end
        end
        WRITE_NONCE : begin
            next_state = WRITE_NONCE;
            next_counter = counter;
            should_write = 1'b0;
            start = 1'b0;
            if(o_RX_DV) begin // there is a valid byte to read
                should_write = 1'b1;
                if(counter == 5'd11) begin // check counter value
                    next_counter = 5'd0; // zero counter if end of array
                    next_state = IDLE; // and go to idle
                end
                else begin
                    // we increment the counter otherwise
                    next_counter = counter + 5'd1;
                end
            end
        end
        WRITE_POS : begin
            next_state = WRITE_POS;
            next_counter = counter;
            should_write = 1'b0;
            start = 1'b0;
            if(o_RX_DV) begin // there is a valid byte to read
                should_write = 1'b1;
                if(counter == 5'd3) begin // check counter value
                    next_counter = 5'd0; // zero counter if end of array
                    next_state = IDLE; // and go to idle
                end
                else begin
                    // we increment the counter otherwise
                    next_counter = counter + 5'd1;
                end
            end
        end
        READ_KEY : begin
            next_counter = 5'd0;
            next_state = IDLE;
            should_write = 1'b0;
            start = 1'b0;
        end
        READ_NONCE : begin
            next_counter = 5'd0;
            next_state = IDLE;
            should_write = 1'b0;
            start = 1'b0;
        end
        READ_POS : begin
            next_counter = 5'd0;
            next_state = IDLE;
            should_write = 1'b0;
            start = 1'b0;
        end
        START : begin
            start = 1'b1;
            next_counter = 5'd0;
            should_write = 1'b0;
            next_state = IDLE;
        end
    endcase
end

assign io_key_0 = {keys[3], keys[2], keys[1], keys[0]};
assign io_key_1 = {keys[7], keys[6], keys[5], keys[4]};
assign io_key_2 = {keys[11], keys[10], keys[9], keys[8]};
assign io_key_3 = {keys[15], keys[14], keys[13], keys[12]};
assign io_key_4 = {keys[19], keys[18], keys[17], keys[16]};
assign io_key_5 = {keys[23], keys[22], keys[21], keys[20]};
assign io_key_6 = {keys[27], keys[26], keys[25], keys[24]};
assign io_key_7 = {keys[31], keys[30], keys[29], keys[28]};

assign io_nonce_0 = {nonces[3], nonces[2], nonces[1], nonces[0]};
assign io_nonce_1 = {nonces[7], nonces[6], nonces[5], nonces[4]};
assign io_nonce_2 = {nonces[11], nonces[10], nonces[9], nonces[8]};

assign io_position = {pos[3], pos[2], pos[1], pos[0]};

endmodule
