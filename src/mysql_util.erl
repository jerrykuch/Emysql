%% Copyright (c) 2009 
%% Bill Warnecke <bill@rupture.com>
%% Jacob Vorreuter <jacob.vorreuter@gmail.com>
%% 
%% Permission is hereby granted, free of charge, to any person
%% obtaining a copy of this software and associated documentation
%% files (the "Software"), to deal in the Software without
%% restriction, including without limitation the rights to use,
%% copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the
%% Software is furnished to do so, subject to the following
%% conditions:
%% 
%% The above copyright notice and this permission notice shall be
%% included in all copies or substantial portions of the Software.
%% 
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
%% OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
%% NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
%% HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
%% WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
%% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
%% OTHER DEALINGS IN THE SOFTWARE.
-module(mysql_util).
-compile(export_all).

length_coded_binary(<<>>) -> {<<>>, <<>>};
length_coded_binary(<<FirstByte:8, Tail/binary>>) ->
	if
		FirstByte =< 250 -> {FirstByte, Tail};
		FirstByte == 251 -> {undefined, Tail};
		FirstByte == 252 ->
			<<Word:16/little, Tail1/binary>> = Tail,
			{Word, Tail1};
		FirstByte == 253 ->
			<<Word:24/little, Tail1/binary>> = Tail,
			{Word, Tail1};
		FirstByte == 254 ->
			<<Word:64/little, Tail1/binary>> = Tail,
			{Word, Tail1};
		true ->
			exit(poorly_formatted_length_encoded_binary)
	end.
	
length_coded_string(<<>>) -> {<<>>, <<>>};
length_coded_string(Bin) ->
    case length_coded_binary(Bin) of
		{undefined, Rest} ->
			{undefined, Rest};
		{Length, Rest} ->
		    case Rest of
		        <<String:Length/binary, Rest1/binary>> -> 
					{binary_to_list(String), Rest1};
		        Bad -> 
					error_logger:error_msg("rest ~p, ~p~n", [Length, Bad]),
					exit(poorly_formatted_length_coded_string)
		    end
	end.

null_terminated_string(<<0, Tail/binary>>, Acc) -> 
	{Acc, Tail};
null_terminated_string(<<_:8>>, _) ->
	exit(poorly_formatted_null_terminated_string);
null_terminated_string(<<H:1/binary, Tail/binary>>, Acc) ->
	null_terminated_string(Tail, <<Acc/binary, H/binary>>).

asciz(Data) when is_binary(Data) ->
    asciz_binary(Data, []);
asciz(Data) when is_list(Data) ->
    {String, [0 | Rest]} = lists:splitwith(fun (C) -> C /= 0 end, Data),
    {String, Rest}.
	
asciz_binary(<<>>, Acc) ->
    {lists:reverse(Acc), <<>>};
asciz_binary(<<0:8, Rest/binary>>, Acc) ->
    {lists:reverse(Acc), Rest};
asciz_binary(<<C:8, Rest/binary>>, Acc) ->
    asciz_binary(Rest, [C | Acc]).
	
bxor_binary(B1, B2) ->
    list_to_binary(dualmap(fun (E1, E2) -> E1 bxor E2 end, binary_to_list(B1), binary_to_list(B2))).

dualmap(_F, [], []) ->
    [];
dualmap(F, [E1 | R1], [E2 | R2]) ->
    [F(E1, E2) | dualmap(F, R1, R2)].
	
hash(S) -> hash(S, 1345345333, 305419889, 7).
hash([C | S], N1, N2, Add) ->
    N1_1 = N1 bxor (((N1 band 63) + Add) * C + N1 * 256),
    N2_1 = N2 + ((N2 * 256) bxor N1_1),
    Add_1 = Add + C,
    hash(S, N1_1, N2_1, Add_1);
hash([], N1, N2, _Add) ->
    Mask = (1 bsl 31) - 1,
    {N1 band Mask , N2 band Mask}.

rnd(N, Seed1, Seed2) ->
    Mod = (1 bsl 30) - 1,
    rnd(N, [], Seed1 rem Mod, Seed2 rem Mod).
rnd(0, List, _, _) ->
    lists:reverse(List);
rnd(N, List, Seed1, Seed2) ->
    Mod = (1 bsl 30) - 1,
    NSeed1 = (Seed1 * 3 + Seed2) rem Mod,
    NSeed2 = (NSeed1 + Seed2 + 33) rem Mod,
    Float = (float(NSeed1) / float(Mod))*31,
    Val = trunc(Float)+64,
    rnd(N - 1, [Val | List], NSeed1, NSeed2).