module pro_uart (
    input  wire        clk,        // 50 MHz Clock (PIN_88)
    input  wire        rst_n,      // Active-low Reset Key0 (PIN_113)
    input  wire [7:0]  sw,         // Slide Switches SW0-SW7
    output reg  [7:0]  led,        // Onboard LEDs (Active-low: 0=ON)
    output reg         vga_hsync,  // VGA H-SYNC (PIN_137)
    output reg         vga_vsync,  // VGA V-SYNC (PIN_139)
    output reg  [3:0]  vga_r,      // VGA Red [3:0] (Pins 122, 121, 120, 119)
    output reg  [3:0]  vga_g,      // VGA Green [3:0] (Pins 132, 129, 126, 125)
    output reg  [3:0]  vga_b       // VGA Blue [3:0] (Pins 136, 135, 134, 133)
);

    // -------------------------------------------------------------------------
    // 1. Clock Divider: 50 MHz -> 25 MHz Pixel Clock
    // -------------------------------------------------------------------------
    reg pix_clk = 1'b0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pix_clk <= 1'b0;
        else
            pix_clk <= ~pix_clk;
    end

    // -------------------------------------------------------------------------
    // 2. Standard 640x480 @ 60 Hz Timing Parameters
    // -------------------------------------------------------------------------
    // Horizontal Timing (Line total = 800 pixels)
    localparam H_VISIBLE    = 640;
    localparam H_FRONT      = 16;
    localparam H_SYNC_PULSE = 96;
    localparam H_BACK       = 48;
    localparam H_TOTAL      = 800;

    // Vertical Timing (Frame total = 525 lines)
    localparam V_VISIBLE    = 480;
    localparam V_FRONT      = 10;
    localparam V_SYNC_PULSE = 2;
    localparam V_BACK       = 33;
    localparam V_TOTAL      = 525;

    reg [9:0] h_cnt = 10'd0;
    reg [9:0] v_cnt = 10'd0;

    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else begin
            if (h_cnt == (H_TOTAL - 1)) begin
                h_cnt <= 10'd0;
                if (v_cnt == (V_TOTAL - 1))
                    v_cnt <= 10'd0;
                else
                    v_cnt <= v_cnt + 10'd1;
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end
        end
    end

    // Generate Active-low H-Sync and V-Sync pulses
    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            vga_hsync <= 1'b1;
            vga_vsync <= 1'b1;
        end else begin
            vga_hsync <= ~((h_cnt >= (H_VISIBLE + H_FRONT)) && 
                           (h_cnt <  (H_VISIBLE + H_FRONT + H_SYNC_PULSE)));
            vga_vsync <= ~((v_cnt >= (V_VISIBLE + V_FRONT)) && 
                           (v_cnt <  (V_VISIBLE + V_FRONT + V_SYNC_PULSE)));
        end
    end

    wire video_on = (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);

    // -------------------------------------------------------------------------
    // 3. LED Hardware Indicator Driver (0 = Glow, 1 = OFF)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led <= 8'b1111_1111;
        end else begin
            case (sw[1:0])
                2'b00: led <= ~8'b0000_0001; // IDLE  (LED0 ON)
                2'b01: led <= ~8'b0000_0010; // RUN   (LED1 ON)
                2'b10: led <= ~8'b0000_0100; // CAL   (LED2 ON)
                2'b11: led <= ~8'b0000_1000; // DIAG  (LED3 ON)
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 4. GUI Dashboard Generation (Instrument State & Switch Visualizer)
    // -------------------------------------------------------------------------
    wire [1:0] mode_sel = sw[1:0];

    // Status Bar calculation: Divides range [X: 80 to 560] into 8 switch regions
    wire [2:0] sw_block_idx = (h_cnt - 10'd80) / 10'd60;
    wire in_sw_bar_zone     = (v_cnt >= 10'd320) && (v_cnt <= 10'd370) && 
                              (h_cnt >= 10'd80)  && (h_cnt <  10'd560);
    wire sw_active_cell     = sw[sw_block_idx];

    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            vga_r <= 4'h0;
            vga_g <= 4'h0;
            vga_b <= 4'h0;
        end else begin
            if (!video_on) begin
                // Blanking during sync and blank intervals
                vga_r <= 4'h0;
                vga_g <= 4'h0;
                vga_b <= 4'h0;
            end else begin
                // Outer Border Frame
                if (h_cnt < 8 || h_cnt >= 632 || v_cnt < 8 || v_cnt >= 472) begin
                    vga_r <= 4'hF; vga_g <= 4'hF; vga_b <= 4'hF; // White border
                end
                // Top Header / Status Banner (Y: 20 -> 70)
                else if (v_cnt >= 20 && v_cnt <= 70 && h_cnt >= 40 && h_cnt <= 600) begin
                    vga_r <= 4'h2; vga_g <= 4'h2; vga_b <= 4'h5; // Slate Blue banner
                end
                // Mode Indicator Display Box (Y: 100 -> 260, X: 120 -> 520)
                else if (v_cnt >= 100 && v_cnt <= 260 && h_cnt >= 120 && h_cnt <= 520) begin
                    case (mode_sel)
                        2'b00: begin // IDLE MODE -> Deep Cyan / Blue
                            vga_r <= 4'h1; vga_g <= 4'h6; vga_b <= 4'hE;
                        end
                        2'b01: begin // RUN MODE -> Bright Green
                            vga_r <= 4'h2; vga_g <= 4'hD; vga_b <= 4'h2;
                        end
                        2'b10: begin // CALIBRATE MODE -> Amber / Orange
                            vga_r <= 4'hF; vga_g <= 4'h9; vga_b <= 4'h0;
                        end
                        2'b11: begin // DIAGNOSTIC / TEST MODE -> Magenta
                            vga_r <= 4'hC; vga_g <= 4'h2; vga_b <= 4'hC;
                        end
                    endcase
                end
                // Switch Status Indicator Bar (Y: 320 -> 370)
                else if (in_sw_bar_zone) begin
                    // Vertical divider gridlines between switch cells
                    if (((h_cnt - 10'd80) % 10'd60 == 0) || ((h_cnt - 10'd80) % 10'd60 == 59)) begin
                        vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h0; // Black delimiter
                    end else if (sw_active_cell) begin
                        vga_r <= 4'h0; vga_g <= 4'hF; vga_b <= 4'h0; // Green when switch is UP (1)
                    end else begin
                        vga_r <= 4'h3; vga_g <= 4'h3; vga_b <= 4'h3; // Dark Grey when DOWN (0)
                    end
                end
                // Background
                else begin
                    vga_r <= 4'h0;
                    vga_g <= 4'h0;
                    vga_b <= 4'h1; // Dark navy background
                end
            end
        end
    end

endmodule