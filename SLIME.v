`timescale 1ns / 1ns // `timescale time_unit/time_precision

module PROJ
	(
		LEDR,
		CLOCK_50,						//	On Board 50 MHz
		// Your inputs and outputs here
		HEX0,
		KEY,							// On Board Keys
		// The ports below are for the VGA output.  Do not change.
		VGA_CLK,   						//	VGA Clock
		VGA_HS,							//	VGA H_SYNC
		VGA_VS,							//	VGA V_SYNC
		VGA_BLANK_N,						//	VGA BLANK
		VGA_SYNC_N,						//	VGA SYNC
		VGA_R,   						//	VGA Red[9:0]
		VGA_G,	 						//	VGA Green[9:0]
		VGA_B   						//	VGA Blue[9:0]
	);

	output [1:0] LEDR; //For Testing
	output [6:0] HEX0; //Counter Display
	input			CLOCK_50;				//	50 MHz
	input	[3:0]	KEY;
	// Do not change the following outputs
	output			VGA_CLK;   				//	VGA Clock
	output			VGA_HS;					//	VGA H_SYNC
	output			VGA_VS;					//	VGA V_SYNC
	output			VGA_BLANK_N;				//	VGA BLANK
	output			VGA_SYNC_N;				//	VGA SYNC
	output	[7:0]	VGA_R;   				//	VGA Red[9:0]
	output	[7:0]	VGA_G;	 				//	VGA Green[9:0]
	output	[7:0]	VGA_B;   				//	VGA Blue[9:0]


	// Create an Instance of a VGA controller
	vga_adapter VGA(
			.resetn(KEY[0]),
			.clock(CLOCK_50),
			.colour(colour),
			.x(x),
			.y(y),
			.plot(writeEn),
			/* Signals for the DAC to drive the monitor. */
			.VGA_R(VGA_R),
			.VGA_G(VGA_G),
			.VGA_B(VGA_B),
			.VGA_HS(VGA_HS),
			.VGA_VS(VGA_VS),
			.VGA_BLANK(VGA_BLANK_N),
			.VGA_SYNC(VGA_SYNC_N),
			.VGA_CLK(VGA_CLK));
		defparam VGA.RESOLUTION = "320x240";
		defparam VGA.MONOCHROME = "FALSE";
		defparam VGA.BITS_PER_COLOUR_CHANNEL = 2; //2bit/channel=6bit color
		defparam VGA.BACKGROUND_IMAGE = "StaticBackground.mif";
	

	//VGA Inputs
	wire [5:0] colour;
	reg [8:0] x; //Max 320, 9-bit
	reg [7:0] y; //Max 240, 8-bit
	wire writeEn;
	assign writeEn = 1'b1; //Set to 1 b/c ROM blocks don't have WriteEnable
	
	//VARIABLES
	wire [1:0] Current; //TEMP for testing
	assign Current = current;
	assign LEDR[1:0] = Current;
	
	reg DoneDraw;
	reg DoneErase;
	reg EnableDraw;
	reg EnableErase;
	
	reg [1:0] Direction;//From FSM, use to set X,Y
	
	
	reg[8:0] XPrint; //Pixel being printed by VGA -> Delayed and put into X,YOut
	reg[7:0] YPrint;

	
	//DRAW / ERASE ALWAYS BLOCK VARIABLES
	reg [8:0] XTemp; //So input X, Y can be manipulated easily in always block
	reg [7:0] YTemp;
	reg [4:0] XAdd; //Used to increment address
	
	reg [16:0] arrayCounterDraw; //17 bits Counts addresses in MIF, one Var for draw, other for Erase
	reg [16:0] arrayCounterErase;
	
	reg [16:0] arrCountStart; //For ERASE, used to increment arrayCounter	
	
	//SET CO-ORDINATES ALWAYS BLOCK VARIABLES
	reg [8:0] XStart; //9 bits, position of charac (top-left pixel)
	reg [7:0] YStart; //8 bits
	reg [8:0] XPrev; //Store previous XStart for use in Erase
	reg [7:0] YPrev;
	
	
	//RATE DIV VARIABLES
	wire [27:0] MaxVal;
	assign MaxVal[27:0] = 28'd5000000; //10Hz = 28'd5000000
	
	reg checkDir;
	reg [27:0] count;
	
	//GET COLOR FROM ROM
	reg [16:0] Address; //17 bits Address in MIF
	
	//PARAM FOR STATES
	localparam 	DRAW = 2'b01,
				ERASE = 2'b10;
	
	//CONTROL BLOCK VARIABLES
	reg [1:0] current, next;
	
	//COLLISION VARIABLES
	reg [3:0] coinCounter; //Max at 5, 4-bits for HEX display
	reg countedA, countedB, countedC, countedD, countedE; //Used to check whether coin was already collected at location, one for each coin
	
	
	
	
//RATE DIVIDER -----------------------
	always @(posedge CLOCK_50) begin
		if (count == MaxVal) begin //MaxVal reached, Reset count, Set checkDir to 1
			count <= 28'd0;
			checkDir <= 1'b1;
		end
		
		else begin //Increment, set checkDir back to 0;
			count <= count + 1;
			checkDir <= 1'b0;
		end
	end


	
//CONTROL -------------------------	
	//STATE TABLE
	always @(*) begin
		case (current)
			DRAW: next = DoneDraw ? ERASE : DRAW; //Draw until done Charac
			ERASE: next = DoneErase ? DRAW : ERASE; //Erase until all of Charac is erased
			default: next = DRAW;
		endcase
	end
	
	
	//DETECT DIRECTION
	always @(posedge CLOCK_50) begin
		if(checkDir == 1'b1) begin
			if(!KEY[3]) //Left
				Direction <= 2'b01;
			else if(!KEY[2]) //Up
				Direction <= 2'b10;
			else if(!KEY[1]) //Right
				Direction <= 2'b11;
			else
				Direction <= 2'b00;
		end
	end
	
	
	//FSM DATAPATH CONTROLS (What is done in each state)
	always @(*) begin
		//Set all signals to 0 at first
		EnableErase = 1'b0;
		EnableDraw = 1'b0;

		case (current)
			DRAW: begin
				EnableDraw = 1'b1; //Draw
				EnableErase = 1'b0;
			end
			
			ERASE: begin
				EnableDraw = 1'b0;
				EnableErase = 1'b1; //Erase
			end
		endcase
	end
	
	
	//UPDATE STATES
	always @(posedge CLOCK_50) begin
		if (!KEY[0])
			current <= DRAW;
		else
			current <= next;
	end



	
//DATAPATH -----------------------------------	
	ram32x4 R1(Address, CLOCK_50, colour); //ROM block w Combined.mif
	
	//CHANGE IN DIRECTION ALWAYS BLOCK
	//Detects change in direction and increments (X,Y) accordingly
	always @(posedge CLOCK_50) begin
		if(!KEY[0]) begin //Assign X,YStart as initial pos
			XStart[8:0] <= 9'd4; //(XStart,YStart) = (4, 178)
			YStart[7:0] <= 8'd178;
		end
		
		else if(checkDir == 1'b1) begin
			if(Direction == 2'b01) begin //Left
				XPrev[8:0] <= XStart;
				XStart[8:0] <= XStart - 1;
			end
			
			else if(Direction == 2'b10) begin //Up
				YPrev[7:0] <= YStart;
				YStart[7:0] <= YStart - 1; //Minus b/c co-ord starts top-left
			end
			
			else if(Direction == 2'b11) begin //Right
				XPrev[8:0] <= XStart;
				XStart[8:0] <= XStart + 1;
			end
			
			else begin //(Direction == 2'b00)
				if(YStart < 8'd178) begin //Drop back down
					YPrev[7:0] <= YStart;
					
					XStart[8:0] <= XStart;
					YStart[7:0] <= YStart + 1;
				end
				else begin				
					XStart[8:0] <= XStart; //Stays same
					YStart[7:0] <= YStart;
				end
			end
		end
	end
	
	
	
	//DRAW / ERASE ALWAYS BLOCK ___________________________________________________
	always @(posedge CLOCK_50) begin //Non-blocking, previous values are assigned to the var		
		if(!KEY[0]) begin
			arrayCounterDraw[16:0] <= 17'd76800;
			arrayCounterErase[16:0] <= 320 * YStart + XStart;
			XAdd[4:0] <= 5'd0;
			arrCountStart <= 320 * YStart + XStart;
			
			DoneDraw <= 1'b0;
			DoneErase <= 1'b1;
		end
		
		
	//DRAW -------------------------------------------------------------
		else if(EnableDraw) begin //Start Drawing: row by row, access Combined
			XTemp[8:0] <= XStart; //XStart = position of top-left corner of sprite
			YTemp[7:0] <= YStart;
			XAdd <= XAdd + 1;
			arrayCounterDraw <= arrayCounterDraw + 1;
			
			if (arrayCounterDraw > 76799 && arrayCounterDraw < 76820) begin
			//76800, 1st row
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp;
				Address <= arrayCounterDraw;
			end
			
			else if (arrayCounterDraw > 77119 && arrayCounterDraw < 77140) begin
			//2nd row
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 1;
				Address <= arrayCounterDraw;
			end
			
			else if (arrayCounterDraw > 77439 && arrayCounterDraw < 77460) begin
			//3rd row
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 2;
				Address <= arrayCounterDraw;
			end	
				
			else if (arrayCounterDraw > 77759 && arrayCounterDraw < 77780) begin
			//4th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 3;
				Address <= arrayCounterDraw;
			end
			
			else if (arrayCounterDraw > 78079 && arrayCounterDraw < 78100) begin
			//5th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 4;
				Address <= arrayCounterDraw;
			end
			
			else if (arrayCounterDraw > 78399 && arrayCounterDraw < 78420) begin
			//6th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 5;
				Address <= arrayCounterDraw;
			end
			
			else if (arrayCounterDraw > 78719 && arrayCounterDraw < 78740) begin
			//7th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 6;
				Address <= arrayCounterDraw;
			end
			
			else if (arrayCounterDraw > 79039 && arrayCounterDraw < 79060) begin
			//8th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 7;
				Address <= arrayCounterDraw;
			end
			
			else if (arrayCounterDraw > 79359 && arrayCounterDraw < 79380) begin
			//9th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 8;
				Address <= arrayCounterDraw;
			end
			
			else if (arrayCounterDraw > 79679 && arrayCounterDraw < 79700) begin
			//10th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 9;
				Address <= arrayCounterDraw;
			end
				
			else if (arrayCounterDraw > 79999 && arrayCounterDraw < 80020) begin
			//11th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 10;
				Address <= arrayCounterDraw;
			end
				
			else if (arrayCounterDraw > 80319 && arrayCounterDraw < 80340) begin
			//12th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 11;
				Address <= arrayCounterDraw;
			end
				
			else if (arrayCounterDraw > 80639 && arrayCounterDraw < 80660) begin
			//13th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 12;
				Address <= arrayCounterDraw;
			end
				
			else if (arrayCounterDraw > 80959 && arrayCounterDraw < 80980) begin
			//14th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 13;
				Address <= arrayCounterDraw;
			end
			
			else if (arrayCounterDraw > 81279 && arrayCounterDraw < 81300) begin
			//15th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 14;
				Address <= arrayCounterDraw;
			end
			
			else if (arrayCounterDraw > 81599 && arrayCounterDraw < 81620) begin
			//16th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 15;
				Address <= arrayCounterDraw;
			end
			
			else if (arrayCounterDraw > 81919 && arrayCounterDraw < 81940) begin 
			//17th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 16;
				Address <= arrayCounterDraw;
			end
			
			else if (arrayCounterDraw > 82239 && arrayCounterDraw < 82260) begin
			//18th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 17;
				Address <= arrayCounterDraw;
			end
			
			else if (arrayCounterDraw > 82559 && arrayCounterDraw < 82580) begin
			//19th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 18;
				Address <= arrayCounterDraw;
			end
			
			else if (arrayCounterDraw > 82879 && arrayCounterDraw < 82900) begin
			//20th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 19;
				Address <= arrayCounterDraw;
			end
			
			else begin
				DoneDraw <= 1'b1;
				DoneErase <= 1'b0;
				XAdd <= 5'b0;
			end
				
		end
	
	//ERASE -----------------------------------------------------------
		else if(EnableErase) begin //Start Erasing: row by row	
			XTemp[8:0] <= XPrev;
			YTemp[7:0] <= YPrev;
			arrayCounterErase <= arrayCounterErase + 1;
			XAdd <= XAdd + 1;
			
			if (arrayCounterErase > (arrCountStart - 1) && arrayCounterErase < (arrCountStart + 20)) begin
			//1st row
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp;
				Address <= arrayCounterErase;
			end
			
			else if (arrayCounterErase > (arrCountStart + 319) && arrayCounterErase < (arrCountStart + 340)) begin
			//(X,Y) + 319, 2nd row
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 1;
				Address <= arrayCounterErase;
			end
			
			else if (arrayCounterErase > (arrCountStart + 638) && arrayCounterErase < (arrCountStart + 659)) begin
			//3rd row
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 2;
				Address <= arrayCounterErase;
			end	
				
			else if (arrayCounterErase > (arrCountStart + 957) && arrayCounterErase < (arrCountStart + 978)) begin
			//4th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 3;
				Address <= arrayCounterErase;
			end
			
			else if (arrayCounterErase > (arrCountStart + 1276) && arrayCounterErase < (arrCountStart + 1297)) begin
			//5th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 4;
				Address <= arrayCounterErase;
			end
			
			else if (arrayCounterErase > (arrCountStart + 1595) && arrayCounterErase < (arrCountStart + 1616)) begin
			//6th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 5;
				Address <= arrayCounterErase;
			end
			
			else if (arrayCounterErase > (arrCountStart + 1914) && arrayCounterErase < (arrCountStart + 1935)) begin
			//7th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 6;
				Address <= arrayCounterErase;
			end
			
			else if (arrayCounterErase > (arrCountStart + 2233) && arrayCounterErase < (arrCountStart + 2254)) begin
			//8th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 7;
				Address <= arrayCounterErase;
			end
			
			else if (arrayCounterErase > (arrCountStart + 2552) && arrayCounterErase < (arrCountStart + 2573)) begin
			//9th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 8;
				Address <= arrayCounterErase;
			end
			
			else if (arrayCounterErase > (arrCountStart + 2871) && arrayCounterErase < (arrCountStart + 2892)) begin
			//10th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 9;
				Address <= arrayCounterErase;
			end
				
			else if (arrayCounterErase > (arrCountStart + 3190) && arrayCounterErase < (arrCountStart + 3211)) begin
			//11th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 10;
				Address <= arrayCounterErase;
			end
				
			else if (arrayCounterErase > (arrCountStart + 3509) && arrayCounterErase < (arrCountStart + 3530)) begin
			//12th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 11;
				Address <= arrayCounterErase;
			end
				
			else if (arrayCounterErase > (arrCountStart + 3828) && arrayCounterErase < (arrCountStart + 3849)) begin
			//13th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 12;
				Address <= arrayCounterErase;
			end
				
			else if (arrayCounterErase > (arrCountStart + 4147) && arrayCounterErase < (arrCountStart + 4168)) begin
			//14th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 13;
				Address <= arrayCounterErase;
			end
			
			else if (arrayCounterErase > (arrCountStart + 4466) && arrayCounterErase < (arrCountStart + 4487)) begin
			//15th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 14;
				Address <= arrayCounterErase;
			end
			
			else if (arrayCounterErase > (arrCountStart + 4785) && arrayCounterErase < (arrCountStart + 4806)) begin
			//16th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 15;
				Address <= arrayCounterErase;
			end
			
			else if (arrayCounterErase > (arrCountStart + 5104) && arrayCounterErase < (arrCountStart + 5125)) begin 
			//17th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 16;
				Address <= arrayCounterErase;
			end
			
			else if (arrayCounterErase > (arrCountStart + 5423) && arrayCounterErase < (arrCountStart + 5444)) begin
			//18th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 17;
				Address <= arrayCounterErase;
			end
			
			else if (arrayCounterErase > (arrCountStart + 5742) && arrayCounterErase < (arrCountStart + 5763)) begin
			//19th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 18;
				Address <= arrayCounterErase;
			end
			
			else if (arrayCounterErase > (arrCountStart + 6061) && arrayCounterErase < (arrCountStart + 6082)) begin
			//20th
				XPrint[8:0] <= XTemp + XAdd;
				YPrint[7:0] <= YTemp + 19;
				Address <= arrayCounterErase;
			end
			
			else begin
				DoneDraw <= 1'b0;
				DoneErase <= 1'b1;
				XAdd <= 5'b0;
			end

		end

		else begin
			DoneDraw <= 1'b0;
			DoneErase <= 1'b1;
		end
		
		//DELAY BY 1 CLOCK EDGE --------------------
		x <= XPrint;
		y <= YPrint;
	end
	
	
	
	
//COLLISION DECTECTION ----------------------------------------------------------
	always @(posedge CLOCK_50) begin
		if(!KEY[0]) begin
			coinCounter <= 4'd0;
			countedA <= 0;
			countedB <= 0;
			countedC <= 0;
			countedD <= 0;
			countedE <= 0;
		end
		
		//Detect collection of coins
		//Check position of pixel printed with co-ord of coin to detect collision
		else if(x == 9'd95 && y == 8'd192) begin
			if(countedA == 0) begin
				coinCounter <= coinCounter + 1; //Collected, increment counter
				countedA <= 1;
			end
			else
				coinCounter <= coinCounter;
		end
		
		else if(x == 9'd108 && y == 8'd192) begin
			if(countedB == 0) begin
				coinCounter <= coinCounter + 1;
				countedB <= 1;
			end
			else
				coinCounter <= coinCounter;
		end
		
		else if(x == 9'd143 && y == 8'd177) begin
			if(countedC == 0) begin
				coinCounter <= coinCounter + 1;
				countedC <= 1;
			end
			else
				coinCounter <= coinCounter;
		end
		
		else if(x == 9'd221 && y == 8'd192) begin
			if(countedD == 0) begin
				coinCounter <= coinCounter + 1;
				countedD <= 1;
			end
			else
				coinCounter <= coinCounter;
		end

		else if(x == 9'd233 && y == 8'd192) begin
			if(countedE == 0) begin
				coinCounter <= coinCounter + 1;
				countedE <= 1;
			end
			else
				coinCounter <= coinCounter;
		end
				
		
		else
			coinCounter <= coinCounter;
	end

	
	//INSTANTIATE HEX MODULE
	hexDisplay hex0(
	  .c3(coinCounter[3]),
	  .c2(coinCounter[2]),
	  .c1(coinCounter[1]),
	  .c0(coinCounter[0]),
	  .a(HEX0[0]),
	  .b(HEX0[1]),
	  .c(HEX0[2]),
	  .d(HEX0[3]),
	  .e(HEX0[4]),
	  .f(HEX0[5]),
	  .g(HEX0[6])
		);
	
endmodule

//HEX DISPLAY MODULE ----------------------------------------------
module hexDisplay(c3, c2, c1, c0, a, b, c, d, e, f, g);
    input c3;
    input c2;
    input c1; 
    input c0;
    
    output a, b, c, d, e, f, g;
  
    assign a = (~c3 & ~c2 & ~c1 & c0)|(~c3 & c2 & ~c1 & ~c0)|(c3 & ~c2 & c1 & c0)|(c3 & c2 & ~c1 & c0);
    assign b = (~c3 & c2 & ~c1 & c0)|(~c3 & c2 & c1 & ~c0)|(c3 & ~c2 & c1 & c0)|
					(c3 & c2 & ~c1 & ~c0)|(c3 & c2 & c1 & ~c0)|(c3 & c2 & c1 & c0);
    assign c = (~c3 & ~c2 & c1 & ~c0)|(c3 & c2 & ~c1 & ~c0)|(c3 & c2 & c1 & ~c0)|(c3 & c2 & c1 & c0);
    assign d = (~c3 & ~c2 & ~c1 & c0)|(~c3 & c2 & ~c1 & ~c0)|(~c3 & c2 & c1 & c0)|
					(c3 & ~c2 & c1 & ~c0)|(c3 & c2 & c1 & c0);
    assign e = (~c3 & ~c2 & ~c1 & c0)|(~c3 & ~c2 & c1 & c0)|(~c3 & c2 & ~c1 & ~c0)|
					(~c3 & c2 & ~c1 & c0)|(~c3 & c2 & c1 & c0)|(c3 & ~c2 & ~c1 & c0);
    assign f = (~c3 & ~c2 & ~c1 & c0)|(~c3 & ~c2 & c1 & ~c0)|(~c3 & ~c2 & c1 & c0)|
					(~c3 & c2 & c1 & c0)|(c3 & c2 & ~c1 & c0);
    assign g = (~c3 & ~c2 & ~c1 & ~c0)|(~c3 & ~c2 & ~c1 & c0)|(~c3 & c2 & c1 & c0)|(c3 & c2 & ~c1 & ~c0);

endmodule

