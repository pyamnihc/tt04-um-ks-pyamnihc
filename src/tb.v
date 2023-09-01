`default_nettype none
`timescale 1ns/1ps

module tb();
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0,tb);
        #1;
    end

    localparam INST_WIDTH = 1;
    localparam ADDR_WIDTH = 7;
    localparam USED_ADDR_WIDTH = 4;
    localparam DATA_WIDTH = 8;
    localparam NUM_CONFIG_REG = 96;
    localparam NUM_STATUS_REG = 32;

    localparam SPI_FRAME_WIDTH = INST_WIDTH+ADDR_WIDTH+DATA_WIDTH;
    localparam CLK_PERIOD = 100;
    localparam SPI_CLK_PERIOD = 1000;
    localparam MAX_CLOCK = 1048576;
    localparam TEST_COUNT = 8;

    reg clk, rst_n;
    reg [DATA_WIDTH-1:0] rand_addr_arr [TEST_COUNT-1:0];
    reg [DATA_WIDTH-1:0] rand_val_arr [NUM_CONFIG_REG+NUM_STATUS_REG-1:0];
    reg [ADDR_WIDTH-1:0] rand_addr;
    reg [DATA_WIDTH-1:0] rand_val;
    integer count_i;
    reg fail_flag;

    assign uio_in[5] = 0;
    assign uio_in[4] = 1;

    initial begin
        clk = 0;
        rst_n = 1;
        #(10*CLK_PERIOD)    init_design();
                            init_spi();
        spi_read(0);
        $display("regmap reset val 0x%0h", spi_read_data);
        test_immediate_write_read();
        test_all_write_then_all_read();

        #(10*CLK_PERIOD)    $finish;
    end

    reg [63:0] clk_count;
    initial clk_count = 0;
    always @(posedge clk) begin
        clk_count <= clk_count + 1;
    end
    
    always #(CLK_PERIOD/2) clk = !clk;

    reg sck_i, cs_ni;
    wire sdi_i, sdo_o;

    // wire up the inputs and outputs
    // reg  clk;
    // reg  rst_n;
    reg  ena;
    wire  [7:0] ui_in;
    wire  [7:0] uio_in;

    wire [6:0] segments = uo_out[6:0];
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    tt_um_spi_register_map tt_um_spi_register_map (
    // include power ports for the Gate Level test
    `ifdef GL_TEST
        .VPWR( 1'b1),
        .VGND( 1'b0),
    `endif
        .ui_in      (ui_in),    // Dedicated inputs
        .uo_out     (uo_out),   // Dedicated outputs
        .uio_in     (uio_in),   // IOs: Input path
        .uio_out    (uio_out),  // IOs: Output path
        .uio_oe     (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
        .ena        (ena),      // enable - goes high when design is selected
        .clk        (clk),      // clock
        .rst_n      (rst_n)     // not reset
        );

//    wire clk_i;
//    assign clk_i = clk;
//    wire rstn_n;
//    assign rstn_n = rst_n;
    assign uio_in[0] = sck_i;
    assign uio_in[1] = sdi_i;
    assign sdo_o = uio_out[2];
    assign uio_in[3] = cs_ni;
    
    assign uio_oe = 8'b1100_0100;

    // tasks
    task init_design();
        begin
            #(10*CLK_PERIOD) rst_n = 1;
            #(10*CLK_PERIOD) rst_n = 0;
            #(10*CLK_PERIOD) rst_n = 1;
        end
    endtask

    task init_spi();
        begin
            #(10*CLK_PERIOD)    cs_ni = 1;
                                sck_i = 0;
        end
    endtask
    
    assign sdi_i = spi_write_frame[SPI_FRAME_WIDTH-1];
    reg [SPI_FRAME_WIDTH-1:0] spi_write_frame;
    task spi_write(
        input [ADDR_WIDTH-1:0] addr,
        input [DATA_WIDTH-1:0] data
    );
        begin
            spi_write_frame = {1'b0, addr, data};
            #(10*CLK_PERIOD)    cs_ni = 0;
                                sck_i = 0;

            repeat(2*(SPI_FRAME_WIDTH)) begin
                #(SPI_CLK_PERIOD/2) sck_i = !sck_i;
                if (sck_i == 0) spi_write_frame = {spi_write_frame[SPI_FRAME_WIDTH-2:0], spi_write_frame[SPI_FRAME_WIDTH-1]};
            end

            #(SPI_CLK_PERIOD/2) cs_ni = 1;
        end
    endtask
   
    reg [SPI_FRAME_WIDTH-1:0] spi_read_frame;
    wire [DATA_WIDTH-1:0] spi_read_data;
    assign spi_read_data = spi_read_frame[DATA_WIDTH-1:0];
    task spi_read(
        input [ADDR_WIDTH-1:0] addr
    );
        begin
            spi_write_frame = {1'b1, addr, 8'b0};
            spi_read_frame = 'b0;
            #(10*CLK_PERIOD)    cs_ni = 0;
                                sck_i = 0;

            repeat(2*(SPI_FRAME_WIDTH)) begin
                #(SPI_CLK_PERIOD/2) sck_i = !sck_i;
                if (sck_i == 0) spi_write_frame = {spi_write_frame[SPI_FRAME_WIDTH-2:0], spi_write_frame[SPI_FRAME_WIDTH-1]};
                if (sck_i == 1) spi_read_frame = {spi_read_frame[SPI_FRAME_WIDTH-2:0], sdo_o};
            end

            #(SPI_CLK_PERIOD/2) cs_ni = 1;
        end
    endtask

    task test_immediate_write_read();
        begin
            fail_flag = 0;
            // immediate write and read
            for (count_i = 0; count_i < TEST_COUNT; count_i = count_i + 1) begin
                rand_addr = {$random} % (1 << USED_ADDR_WIDTH);
                rand_val = {$random} % (1 << DATA_WIDTH);

                if (rand_addr < NUM_CONFIG_REG) begin
                    #(10*CLK_PERIOD) spi_write(rand_addr, rand_val);
                end else begin
                    if (rand_addr < NUM_CONFIG_REG + NUM_STATUS_REG/2) rand_val = 8'h00;
                    else if ((rand_addr >= NUM_CONFIG_REG + NUM_STATUS_REG/2) &&
                                (rand_addr < NUM_CONFIG_REG+NUM_STATUS_REG)) rand_val = 8'hff;
                    else rand_val = 8'bXXXX_XXXX;
                end

                #(10*CLK_PERIOD) spi_read(rand_addr);
                $display("addr: 0x%0h, val: 0x%0h, read val: 0x%0h", rand_addr, rand_val, spi_read_data);
                if (spi_read_data != rand_val) begin
                    $display("Immediate write and read failed for addr: ",
                                "0x%0h, data: 0x%0h, readback: 0x%0h", rand_addr, rand_val, spi_read_data);
                    fail_flag = 1;
                end
            end
            if (fail_flag == 0) begin
                $display("SUCCESS:Immediate write and read");
            end
        end
    endtask

    task test_all_write_then_all_read();
        begin
            fail_flag = 0;
            // all write then all read
            for (count_i = 0; count_i < TEST_COUNT; count_i = count_i + 1) begin
                rand_addr = {$random} % (1 << USED_ADDR_WIDTH);
                rand_val = {$random} % (1 << DATA_WIDTH);

                if (rand_addr < NUM_CONFIG_REG) begin
                    #(10*CLK_PERIOD) spi_write(rand_addr, rand_val);
                end else begin
                    if (rand_addr < NUM_CONFIG_REG + NUM_STATUS_REG/2) rand_val = 8'h00;
                    else if ((rand_addr >= NUM_CONFIG_REG + NUM_STATUS_REG/2) &&
                                (rand_addr < NUM_CONFIG_REG+NUM_STATUS_REG)) rand_val = 8'hff;
                    else rand_val = 8'bXXXX_XXXX;
                end
                rand_addr_arr[count_i] = rand_addr;
                rand_val_arr[rand_addr] = rand_val;

                $display("addr: 0x%0h, val: 0x%0h", rand_addr, rand_val);
            end
            for (count_i = 0; count_i < TEST_COUNT; count_i = count_i + 1) begin
                #(10*CLK_PERIOD) spi_read(rand_addr_arr[count_i]);
                $display("read val: 0x%0h", spi_read_data);

                if (spi_read_data != rand_val_arr[rand_addr_arr[count_i]]) begin
                        $display("all write followed by all read failed for", 
                                    " addr: 0x%0h, readback: 0x%0h", 
                                    rand_addr_arr[count_i], spi_read_data);
                        fail_flag = 1;
                end
            end
            if (fail_flag == 0) begin
                $display("SUCCESS:all write followed by all read");
            end
        end
    endtask

endmodule
