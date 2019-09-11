Peak-Detector Data Processor
==========================

Author
------

Ziran He


Date
----

29 Mar 2019


Description
-----------

The objective of assignment 2 is using the CMOD A7 FPGA to achieve a peak detector in VHDL. The peak detector is composed of a Data Generator, Data Consumer, Command Processor, Transmitter (TX) and Receiver (RX). There are four main functions of this peak detector. First, all printable characters typed in the terminal will be echoed. Moreover, if ‘aNNN’ or ‘ANNN’ (N is a decimal number between 0-9) is typed in PuTTY, NNN number of bytes of data in hexadecimal format will be sent to the computer and displayed in the terminal. Secondly, if ‘l’ or ‘L’ is typed after this, seven sets of data will be extracted from the whole data sequence and displayed under the command line. Note that if the peak is at the end of the data sequence, and the number of bytes of data after the peak is smaller than 3, then only the valid number of bytes of data after the peak will be updated. The characteristic of this data sequence is the middle number of the sequence which is the peak (maximum) of the whole data. The three numbers before and after the peak which are the corresponding bytes in the data sequence requested. Thirdly, if ‘p’ or ‘P’ is typed, the peak and the index of the peak in the data will be printed in the terminal. Finally, all other printable characters that serve no function when typed will be echoed in the terminal.
In this project, the two components that needed to be developed are Data Consumer and Command Processor. The group is divided into two teams and each team designs the corresponding components. The details about the team composition are provided in the next section. In the following sections, team project plan, Design of Data consumer, Design of Command processor will be illustrated.

Design approach of Data Consumer
------

There are 3 main design stages of the data consumer, which are the data retrieval following the two-phase handshaking protocol, peak comparing and shifting, and state machine. The fully functional and synthesisable Data Consumer is achieved in this submission provided with the black box reference of the Command Processor.

1.Two-phase handshaking protocol
------
The theory of the two-phase handshaking protocol is detecting the change of the control line signal rather than detecting the absolute value of the control line signal. As shown in Figure 3, there are two blocks which are ctrlDelay and ctrlIn_detected which are two processes in the source code. The function of the ctrlDelay process is that it stores the value of the ctrlIn and ctrlOut_reg (ctrlOut) and they are updated at every clock cycle. The ctrlIn_detected is the output of ctrlIn XOR ctrlIn_delayed. The function of this process is that each time ctrlIn_detected is ‘1’, this means that the ctrlIn is different to the ctrlIn_delayed which means that the value of ctrlIn is changed and the new data is available on the data line. At this time, the value of the start will be checked. If start is ‘1’, then the value of ctrlOut_reg (ctrlOut) will be set to ‘NOT ctrlOut_delayed’. This means that rather than setting the value of ctrlOut_reg (ctrlOut) to a specific value, the ctrlOut_reg (ctrlOut) only needs to be different from its current value (ctrlOut_delayed’).
Note that the reason for using the ctrlOut_reg is the output port (ctrlOut) cannot be read. Since the ctrlOut needs to be read by ctrlOut_delayed, the value of ctrlOut must be registered (ctrlOut_reg).

2.Peak comparing and shifting
------
In order to output the dataResults and maxIndex, there are four main blocks (processes) are used in this design which are dataShifter, Comparator, peakShifter, counter (and BCD_counter). The use of the BCD_counter will be discussed in the improvement section.
For the dataShifter, it is a process that keeps shifting the new data into a char array (dataHolder) if ctrlIn_detected is ‘1’ at the rising edge of the clock. The length of this char array is 4, this is because when the new peak is detected, only three amounts of previous data are interested. In addition, if the new data is a peak, in the dataHolder, the peak will be the position 0 of the dataHolder and the three previous data are the position 1, 2, 3 respectively.
For the comparator, new data is shifted into dataHolder, simultaneously, the new data is also sent to the comparator and compared with the current peak. Initially, If the value of data is bigger than the current peak, then the value of peak will be updated and enShift_Peak will be activated to enable the peakShifter. In addition, the current counter value will be registered for the maxIndex. Secondly, if the data is smaller than the current peak, then the peak value will not be updated. However, in this design, one extreme case is considered. For example, a set of data which are all negative numbers. In this design, since the initial peak value is set to 0, it makes sense to shift the negative number after the current peak which is 0 (if there has been any new peak yet). In this case, maxIndex will be marked as -1 pretending that the peak 0 is a data that has been shifted in before the first data. This maxIndex will be used to find which position of dataResult to shift into the new data. This also requires that the count value smaller than 3. The reason for this is that if the data sequences are all negative numbers, only the first three will be shifted in to dataResult.
Peakshifter is one of the most important processes in this design. Firstly, if enShift_Peak is TRUE, this means that the new peak is detected. Consequently, all the data stored in the dataHolder will be shifted into the dataResults which is one of the outputs. When the following data is received, if there is no new peak, the three following data will be shifted into the corresponding places of the dataResults. Secondly, if there is no peak, and the count is still smaller than (maxIndex + 4), then the new data will be shifted into dataResult after the peak. The reason for 4 is there 3 numbers after the peak, and there is one clock cycle delay in this shifting process.
In addition, following the specification, if the number of bytes of data following the peak is less than 3 before the sequence is finished, only the corresponding bytes will be updated in the dataResults.

3.State machine
-------
The design of the state machine is provided in Figure 4. There are four states in total which are INIT, FIRST, SECOND, and THIRD. In order to avoid latches in case of missing the conditional statement, all the used signals in this process are assigned to a default value at the beginning of the process.
At the INIT state, the clearCount signal is unconditionally TRUE to clear dataHolder and counters, and initialise peak, maxIndex and dataResults. If start is ‘1’ the Command Processor requests data from the Data Consumer, ctrlOut_reg (ctrlOut) is set to NOT ctrlOut_Delayed and the state transitions to state FIRST. This triggers the change in the data request line between the Data consumer and Data Generator. Hence, new data will be updated on the data line.
At the FIRST state, the ctrlIn_detected will be monitored. When ctrlIn_detected is ‘1’, this means the new data is available on the data line, then the dataReady is set to high to notify the Command Processor that the new byte is sent to it and the next state will be the SECOND state. In addition, the counter will be enabled.

At the SECOND state, firstly, the value of count will be compared to numWords_integer. If the count is greater or equal to numWords_integer, the number of bytes that have been sent to Command processor is enough. Then, the next state will be the THIRD state. On the other hand, if count is smaller than numWords_integer, this means that the number of bytes that have been sent to the Command processor is not enough yet, and if the start is ‘1’, then the next state returns to FIRST again and ctrlOut_reg (ctrlOut) is set to NOT ctrlOut_Delayed. This will trigger the two-phase handshaking protocol to request the new data from the Data Generator.
The THIRD state is the finishing state. This state can only be entered when all the required number of bytes have already been sent to the Command Processor. At this state, peakshiftDone will be detected, if peakshiftDone is TRUE, then the next state will be back to the INIT state. However, if it is FALSE, the counter will still be enabled. The reason for this is that the index of the byte that will be updated in dataResults depends on the relationship between the value of count and maxIndex_Int. Also, there is one clock cycle delay and it might affect the corner case. By calculating the relationship between these two numbers, it can be found that (maxIndex_Int – count + 4) will return 2, 1, and 0 each time when count increases after found the new peak.







