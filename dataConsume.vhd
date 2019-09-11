LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.common_pack.ALL;

ENTITY dataConsume IS
  PORT (
		clk: IN STD_LOGIC;
		reset: IN STD_LOGIC; -- asynchronous reset
		start: IN STD_LOGIC; -- goes high when command requests data
		numWords_bcd: IN BCD_ARRAY_TYPE(2 DOWNTO 0);
		ctrlIn: IN STD_LOGIC; -- changes when data is ready on the data line
		ctrlOut: OUT STD_LOGIC; -- changes when request data from Data Generator
		data: IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		dataReady: OUT STD_LOGIC;
		byte: OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		seqDone: OUT STD_LOGIC;
		maxIndex: OUT BCD_ARRAY_TYPE(2 DOWNTO 0);
		dataResults: OUT CHAR_ARRAY_TYPE(0 TO RESULT_BYTE_NUM-1) -- index 3 holds the peak
  	);
END;

ARCHITECTURE arch OF dataConsume IS 
  TYPE STATE_TYPE IS (INIT,FIRST,SECOND,THIRD);
  SIGNAL curState, nextState: STATE_TYPE;
  SIGNAL ctrlOut_reg,ctrlOut_delayed,ctrlIn_delayed,ctrlIn_detected: STD_LOGIC := '0';
  SIGNAL numWords_integer, count, peak, maxIndex_Int: INTEGER RANGE -999 TO 999;
  SIGNAL clearCount, enCount, enShift_Peak, peakshiftDone: BOOLEAN := FALSE;
  SIGNAL dataHolder: CHAR_ARRAY_TYPE (0 TO 3);
  SIGNAL BCD_count: BCD_ARRAY_TYPE(2 DOWNTO 0);
  
  -- Active this if integer to BCD converter is used
  --SIGNAL enShift_NoPeak: BOOLEAN := FALSE;
  
BEGIN
ctrlOut <= ctrlOut_reg;
ctrlIn_detected <= ctrlIn XOR ctrlIn_delayed;
byte <= data;
----------------------------------------------------------------------------
  nextStateLogic: PROCESS(curState,start,count,numWords_integer,peakshiftDone,ctrlIn_detected)
  BEGIN
    CASE curState IS  
	  WHEN INIT =>
	    IF start = '1' THEN -- Command Processor requests data
	      nextState <= FIRST;
	    ELSE
          nextState <= INIT;
        END IF;
      
      WHEN FIRST =>
        IF ctrlIn_detected = '1' THEN -- Hand shake protocol, data is available on the data line
          nextState <= SECOND;
        ELSE
          nextState <= FIRST;
        END IF;
      
      WHEN SECOND =>
        IF count < numWords_integer THEN -- More bytes need to be sent
          IF start = '1' THEN -- Command Processor requests data
            nextState <= FIRST;
          ELSE -- The bytes have been sent to the Command Processor is enough
            nextState <= SECOND;
          END IF;
        ELSE
          nextState <= THIRD;  
        END IF;
       
      WHEN THIRD =>
        IF peakshiftDone = TRUE THEN -- Waiting for the shift process to be finished
          nextState <= INIT;
        ELSE
          nextState <= THIRD;
        END IF;

      WHEN OTHERS =>
        nextState <= INIT; 
        
    END CASE;
  END PROCESS; --nextStateLogic
    
----------------------------------------------------------------------------
  controller: PROCESS(curState,start,count,numWords_integer,peakshiftDone,ctrlOut_delayed,numWords_bcd,ctrlIn_detected,data)
  BEGIN
    -- Default values to aviod latches
    dataReady <= '0';
    seqDone <= '0';
    clearCount <= FALSE;
    enCount <= FALSE;
    numWords_integer <= TO_INTEGER(UNSIGNED(numWords_bcd(2))) * 100 + TO_INTEGER(UNSIGNED(numWords_bcd(1))) * 10 + TO_INTEGER(UNSIGNED(numWords_bcd(0))) * 1;
    ctrlOut_reg <= ctrlOut_delayed;

    CASE curState IS
      WHEN INIT =>
        clearCount <= TRUE; -- Force clear at first time. In case the reset is not pressed.
        numWords_integer <= 0;
 	    IF start = '1' THEN -- Command Processor requests data
	      ctrlOut_reg <= NOT ctrlOut_delayed; -- Request data from data generator 
        END IF;

      WHEN FIRST =>
        IF ctrlIn_detected = '1' THEN -- Hand shake protocol, data is available on the data line
          enCount <= TRUE; -- Increase the count
          dataReady <= '1';
        END IF;

      WHEN SECOND =>
        IF count < numWords_integer THEN
          IF start = '1' THEN -- Command Processor requests data
            ctrlOut_reg <= NOT ctrlOut_delayed; -- Request data from data generator 
          END IF;
        END IF;

      WHEN THIRD => 
        IF peakshiftDone = TRUE THEN -- Waiting for the shift process to be finished
          seqDone <= '1';  -- Sequence done
          clearCount <= TRUE; -- Clear count, BCD_count, dataShifter_reg, peak, maxIndex_Int, maxIndex, dataResults 
        ELSE
          enCount <= TRUE;
        END IF;

    END CASE;
  END PROCESS; --controller
  
----------------------------------------------------------------------------
  dataShifter: PROCESS(clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF clearCount = TRUE THEN
        dataHolder <= (OTHERS => X"00"); -- clear dataHolder
      ELSIF ctrlIn_detected = '1' THEN -- New data is available on the data line
        FOR i IN 3 DOWNTO 1 LOOP -- Static boundary for loop
          dataHolder(i) <= dataHolder(i-1); --Shift previous data to right
        END LOOP;
        dataHolder(0) <= data; --Shift in the new data
      END IF;
    END IF;
  END PROCESS; --dataShifter
----------------------------------------------------------------------------
  Comparator: PROCESS(clk)
  BEGIN
    IF rising_edge(clk) THEN
      enShift_Peak <= FALSE; -- Default value
      --enShift_NoPeak <= FALSE; -- Active this if integer to BCD process is used
      IF clearCount = TRUE THEN
        peak <= 0; -- clear the peak
        maxIndex_Int <= 0; 
        maxIndex <= (OTHERS => "0000");
      ELSIF TO_INTEGER(SIGNED(data)) > peak THEN
        peak <= TO_INTEGER(SIGNED(data)); -- New peak detected
        maxIndex_Int <= count; -- Mark the integer of the index of the new peak as a reference, will be used when shifting the 3 bytes after the peak
        maxIndex <= BCD_count; -- The index of the new peak in the data sequence
        enShift_Peak <= TRUE; -- Shift new peak
      ELSIF count <= 3 AND peak = 0 THEN
        maxIndex_Int <= -1; -- Question marks will be printed, since there is no peak
        maxIndex <= (OTHERS => "1111");
        --enShift_NoPeak <= TRUE; -- Active this if integer to BCD process is used
      END IF;
    END IF;
  END PROCESS; --Comparator
----------------------------------------------------------------------------
  peakShifter: PROCESS(clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF clearCount = TRUE THEN
        dataResults <= (OTHERS => X"00"); -- clear dataResults
    
      ELSIF enShift_Peak = TRUE THEN -- Peak detected
        peakshiftDone <= FALSE; -- peakshiftDone unfinished
        FOR i IN 3 TO 6 LOOP -- Static boundary loop
          dataResults(i) <= dataHolder(i-3); -- Shift the dataHolder in to dataResults
        END LOOP;
      
      ELSIF 0<= maxIndex_Int-count+4 AND maxIndex_Int-count+4 <=2 THEN
      -- maxIndex_Int-count+4, the reason of using this is the desired index of dataResults here are 2, 1, 0. Since the maxIndex_Int can be used as a reference
      -- and the count is keep increasing, maxIndex_Int - count + 4 will give 2, 1, 0 in each data cycle.
        IF count < numWords_integer+1 THEN -- Since dataHolder takes one clock cycle, this shifting process is one clock cycle delayed. Hence, + 1.
          dataResults(maxIndex_Int-count+4) <= dataHolder(0); -- The most recent data is always at the final postion of dataHolder()
        END IF;
        IF (maxIndex_Int-count+4) = 0 THEN
          peakshiftDone <= TRUE; -- When the final position of dataResults(6) is updated, this peakshift process is done. 
        END IF;
      END IF;
    END IF;
END PROCESS; -- peakShifter
------------------------------------------------------------------------------
-- In the initial design, the integer is used and the maxIndex_Int needs to be converted into BCD format.  This process can do this.
-- However, I found that the division operation takes more time than other operations.  By using the BCD counter, the division 
-- operations can be removed.  As a result, the WNS can be reduced.  More details are discussed in the report.
-----------------------------------------------------------------------------
--  BCD_maxIndex: PROCESS(clk) --integer to BCD process
--  BEGIN
--    IF rising_edge(clk) THEN
--      IF clearCount =TRUE THEN
--        maxIndex <= (OTHERS => "0000");
--      ELSIF enShift_Peak = TRUE OR enShift_NoPeak = TRUE THEN -- 3 digits number 
--        IF maxIndex_Int  >= 100 THEN -- Higher Than 100
--          maxIndex(2) <= std_logic_vector(TO_UNSIGNED(maxIndex_Int/100,4)); -- For example, 999/100 = 9 , 9 = (1001) in binary
--          maxIndex(1) <= std_logic_vector(TO_UNSIGNED((maxIndex_Int REM 100)/10,4)); -- 999 REM 100 = 99, 99/10 = 9, 9 = (1001) in binary
--          maxIndex(0) <= std_logic_vector(TO_UNSIGNED((maxIndex_Int REM 100)REM 10,4)); -- 999 REM 100 = 99, 99 REM 10 = 9, 9 = (1001) in binary
--        ELSIF maxIndex_Int  >= 10 THEN -- 2 dights number
--          maxIndex(2) <= "0000";
--          maxIndex(1) <= std_logic_vector(TO_UNSIGNED(maxIndex_Int/10,4));
--          maxIndex(0) <= std_logic_vector(TO_UNSIGNED((maxIndex_Int REM 10),4));
--        ELSIF maxIndex_Int >= 1 THEN -- 1 digit number
--          maxIndex(2) <= "0000";
--          maxIndex(1) <= "0000";
--          maxIndex(0) <= std_logic_vector(TO_UNSIGNED(maxIndex_Int,4));
--        ELSIF maxIndex_Int = -1 THEN
--          maxIndex <= (OTHERS => "1111");
--        END IF;
--      END IF;
--    END IF;
--  END PROCESS; --BCD_maxIndex
----------------------------------------------------------------------------
 ctrlDelay: PROCESS(clk) -- Used for handshaking protocol
 BEGIN
   IF rising_edge(clk) THEN
     ctrlOut_delayed <= ctrlOut_reg; -- One clock delayed version of the ctrlOut_reg
	 ctrlIn_delayed <= ctrlIn; -- -- One clock delayed version of the ctrlIn
   END IF;
   END PROCESS; --ctrlDelay
----------------------------------------------------------------------------
  seq_state: PROCESS (clk, reset) 
  BEGIN
    IF reset = '1' THEN
      curState <= INIT;
    ELSIF rising_edge(clk) THEN
      curState <= nextState; -- change the state at the rising edge of the clock
    END IF;
    END PROCESS; -- seq_state
    
----------------------------------------------------------------------------  
  counter: PROCESS(clk)
  BEGIN
   IF rising_edge(clk) THEN
      IF clearCount = TRUE THEN
        count <= 0;
      ELSIF enCount = TRUE THEN
        count <= count + 1;
      END IF;
    END IF;
  END PROCESS; --counter
----------------------------------------------------------------------------
  BCD_counter: PROCESS(clk)
  BEGIN
    IF rising_edge(clk) THEN
      IF clearCount = TRUE THEN
        BCD_count <= (OTHERS => "0000");
      ELSIF enCount = TRUE THEN
        IF TO_INTEGER(UNSIGNED(BCD_count(0))) < 9 THEN --Not carry, increase BCD_count(0)
          BCD_count(0) <= STD_LOGIC_VECTOR(TO_UNSIGNED( (TO_INTEGER(UNSIGNED(BCD_count(0))) + 1)  ,4));
        ELSE -- carry
          BCD_count(0) <= "0000"; 
          IF TO_INTEGER(UNSIGNED(BCD_count(1))) < 9 THEN -- Not carry, increase BCD_count(1)
            BCD_count(1) <= STD_LOGIC_VECTOR(TO_UNSIGNED( (TO_INTEGER(UNSIGNED(BCD_count(1))) + 1)  ,4));
          ELSE -- carry
            BCD_count(1) <= "0000"; -- carry, increase BCD_count(2)
            IF TO_INTEGER(UNSIGNED(BCD_count(2))) < 9 THEN -- Not carry, increase BCD_count(2)
              BCD_count(2) <= STD_LOGIC_VECTOR(TO_UNSIGNED( (TO_INTEGER(UNSIGNED(BCD_count(2))) + 1)  ,4));
            ELSE -- 999, maximum
              BCD_count(2) <= "0000"; 
            END IF;
          END IF;
        END IF;
 
      END IF;
    END IF;
  END PROCESS; --BCD_counter

END; --arch_dataComsume
