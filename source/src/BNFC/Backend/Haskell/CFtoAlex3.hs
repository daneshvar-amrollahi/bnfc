{-
    BNF Converter: Alex 3.0 Generator
    Copyright (C) 2012  Author:  Antti-Juhani Kaijanaho
    Copyright (C) 2004  Author:  Peter Gammie
    (C)opyright 2003, {aarne,markus,peteg} at cs dot chalmers dot se

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1335, USA
-}

module BNFC.Backend.Haskell.CFtoAlex3 (cf2alex3) where

import BNFC.CF
import Data.List

-- For BNFC.Backend.Haskell.RegToAlex, see below.
import AbsBNF
import Data.Char

cf2alex3 :: String -> String -> String -> Bool -> Bool -> CF -> String
cf2alex3 name errMod shareMod shareStrings byteStrings cf =
  unlines $ intercalate [""] [
    prelude name errMod shareMod shareStrings byteStrings,
    cMacros,
    rMacros cf,
    restOfAlex shareMod shareStrings byteStrings cf
   ]

prelude :: String -> String -> String -> Bool -> Bool -> [String]
prelude name _ shareMod shareStrings byteStrings = [
  "-- -*- haskell -*-",
  "-- This Alex file was machine-generated by the BNF converter",
  "{",
  "{-# OPTIONS -fno-warn-incomplete-patterns #-}",
  "{-# OPTIONS_GHC -w #-}",
  "module " ++ name ++ " where",
  "",
  -- "import " ++ errMod,
  if shareStrings then "import " ++ shareMod else "",
  if byteStrings  then "import qualified Data.ByteString.Char8 as BS" else "",
  "import qualified Data.Bits",
  "import Data.Word (Word8)",
  "import Data.Char (ord)",
  "}",
  ""
  ]

cMacros :: [String]
cMacros = [
  "$c = [A-Z\\192-\\221] # [\\215]  -- capital isolatin1 letter (215 = \\times) FIXME",
  "$s = [a-z\\222-\\255] # [\\247]  -- small   isolatin1 letter (247 = \\div  ) FIXME",
  "$l = [$c $s]         -- letter",
  "$d = [0-9]           -- digit",
  "$i = [$l $d _ ']     -- identifier character",
  "$u = [. \\n]          -- universal: any character"
  ]

rMacros :: CF -> [String]
rMacros cf =
  let symbs = cfgSymbols cf
  in
  (if null symbs then [] else [
   "@rsyms =    -- symbols and non-identifier-like reserved words",
   "   " ++ unwords (intersperse "|" (map mkEsc symbs))
   ])
 where
  mkEsc = unwords . esc
  esc s = if null a then rest else show a : rest
      where (a,r) = span isAlphaNum s
            rest = case r of
                       [] -> []
                       (c:xs) -> s : esc xs
                         where s = if isPrint c then ['\\',c]
                                                else '\\':show (ord c)

restOfAlex :: String -> Bool -> Bool -> CF -> [String]
restOfAlex _ shareStrings byteStrings cf = [
  ":-",
  lexComments (comments cf),
  "$white+ ;",
  pTSpec (cfgSymbols cf),

  userDefTokenTypes,
  ident,

  ifC catString ("\\\" ([$u # [\\\" \\\\ \\n]] | (\\\\ (\\\" | \\\\ | \\' | n | t)))* \\\"" ++
                  "\n    { tok (\\p s -> PT p (TL $ share $ unescapeInitTail s)) }"),
  ifC catChar    "\\\' ($u # [\\\' \\\\] | \\\\ [\\\\ \\\' n t]) \\'\n    { tok (\\p s -> PT p (TC $ share s))  }",
  ifC catInteger "$d+\n    { tok (\\p s -> PT p (TI $ share s))    }",
  ifC catDouble  "$d+ \\. $d+ (e (\\-)? $d+)?\n    { tok (\\p s -> PT p (TD $ share s)) }",
  "",
  "{",
  "",
  "tok :: (Posn -> String -> Token) -> (Posn -> String -> Token)",
  "tok f p s = f p s",
  "",
  "share :: "++stringType++" -> "++stringType,
  "share = " ++ if shareStrings then "shareString" else "id",
  "",
  "data Tok =",
  "   TS !"++stringType++" !Int    -- reserved words and symbols",
  " | TL !"++stringType++"         -- string literals",
  " | TI !"++stringType++"         -- integer literals",
  " | TV !"++stringType++"         -- identifiers",
  " | TD !"++stringType++"         -- double precision float literals",
  " | TC !"++stringType++"         -- character literals",
  userDefTokenConstrs,
  " deriving (Eq,Show,Ord)",
  "",
  "data Token =",
  "   PT  Posn Tok",
  " | Err Posn",
  "  deriving (Eq,Show,Ord)",
  "",
  "printPosn :: Posn -> String",
  "printPosn (Pn _ l c) = \"line \" ++ show l ++ \", column \" ++ show c",
  "",
  "tokenPos :: [Token] -> String",
  "tokenPos (t:_) = printPosn (tokenPosn t)",
  "tokenPos [] = \"end of file\"",
  "",
  "tokenPosn :: Token -> Posn",
  "tokenPosn (PT p _) = p",
  "tokenPosn (Err p) = p",
  "",
  "tokenLineCol :: Token -> (Int, Int)",
  "tokenLineCol = posLineCol . tokenPosn",
  "",
  "posLineCol :: Posn -> (Int, Int)",
  "posLineCol (Pn _ l c) = (l,c)",
  "",
  "mkPosToken :: Token -> ((Int, Int), String)",
  "mkPosToken t@(PT p _) = (posLineCol p, prToken t)",
  "",
  "prToken :: Token -> String",
  "prToken t = case t of",
  "  PT _ (TS s _) -> s",
  "  PT _ (TL s)   -> show s",
  "  PT _ (TI s)   -> s",
  "  PT _ (TV s)   -> s",
  "  PT _ (TD s)   -> s",
  "  PT _ (TC s)   -> s",
  "  Err _         -> \"#error\"",
  userDefTokenPrint,
  "",
  "data BTree = N | B "++stringType++" Tok BTree BTree deriving (Show)",
  "",
  "eitherResIdent :: ("++stringType++" -> Tok) -> "++stringType++" -> Tok",
  "eitherResIdent tv s = treeFind resWords",
  "  where",
  "  treeFind N = tv s",
  "  treeFind (B a t left right) | s < a  = treeFind left",
  "                              | s > a  = treeFind right",
  "                              | s == a = t",
  "",
  "resWords :: BTree",
  "resWords = " ++ show (sorted2tree $ cfTokens cf),
  "   where b s n = let bs = "++stringPack++" s",
  "                  in B bs (TS bs n)",
  "",
  "unescapeInitTail :: "++stringType++" -> "++stringType++"",
  "unescapeInitTail = "++stringPack++" . unesc . tail . "++stringUnpack++" where",
  "  unesc s = case s of",
  "    '\\\\':c:cs | elem c ['\\\"', '\\\\', '\\\''] -> c : unesc cs",
  "    '\\\\':'n':cs  -> '\\n' : unesc cs",
  "    '\\\\':'t':cs  -> '\\t' : unesc cs",
  "    '\"':[]    -> []",
  "    c:cs      -> c : unesc cs",
  "    _         -> []",
  "",
  "-------------------------------------------------------------------",
  "-- Alex wrapper code.",
  "-- A modified \"posn\" wrapper.",
  "-------------------------------------------------------------------",
  "",
  "data Posn = Pn !Int !Int !Int",
  "      deriving (Eq, Show,Ord)",
  "",
  "alexStartPos :: Posn",
  "alexStartPos = Pn 0 1 1",
  "",
  "alexMove :: Posn -> Char -> Posn",
  "alexMove (Pn a l c) '\\t' = Pn (a+1)  l     (((c+7) `div` 8)*8+1)",
  "alexMove (Pn a l c) '\\n' = Pn (a+1) (l+1)   1",
  "alexMove (Pn a l c) _    = Pn (a+1)  l     (c+1)",
  "",
  "type Byte = Word8",
  "",
  "type AlexInput = (Posn,     -- current position,",
  "                  Char,     -- previous char",
  "                  [Byte],   -- pending bytes on the current char",
  "                  "++stringType++")   -- current input string",
  "",
  "tokens :: "++stringType++" -> [Token]",
  "tokens str = go (alexStartPos, '\\n', [], str)",
  "    where",
  "      go :: AlexInput -> [Token]",
  "      go inp@(pos, _, _, str) =",
  "               case alexScan inp 0 of",
  "                AlexEOF                   -> []",
  "                AlexError (pos, _, _, _)  -> [Err pos]",
  "                AlexSkip  inp' len        -> go inp'",
  "                AlexToken inp' len act    -> act pos ("++stringTake++" len str) : (go inp')",
  "",
  "alexGetByte :: AlexInput -> Maybe (Byte,AlexInput)",
  "alexGetByte (p, c, (b:bs), s) = Just (b, (p, c, bs, s))",
  "alexGetByte (p, _, [], s) =",
  "  case "++stringUncons++" s of",
  "    "++stringNilP++"  -> Nothing",
  "    "++stringConsP++" ->",
  "             let p'     = alexMove p c",
  "                 (b:bs) = utf8Encode c",
  "              in p' `seq` Just (b, (p', c, bs, s))",
  "",
  "alexInputPrevChar :: AlexInput -> Char",
  "alexInputPrevChar (p, c, bs, s) = c",
  "",
  "-- | Encode a Haskell String to a list of Word8 values, in UTF8 format.",
  "utf8Encode :: Char -> [Word8]",
  "utf8Encode = map fromIntegral . go . ord",
  " where",
  "  go oc",
  "   | oc <= 0x7f       = [oc]",
  "",
  "   | oc <= 0x7ff      = [ 0xc0 + (oc `Data.Bits.shiftR` 6)",
  "                        , 0x80 + oc Data.Bits..&. 0x3f",
  "                        ]",
  "",
  "   | oc <= 0xffff     = [ 0xe0 + (oc `Data.Bits.shiftR` 12)",
  "                        , 0x80 + ((oc `Data.Bits.shiftR` 6) Data.Bits..&. 0x3f)",
  "                        , 0x80 + oc Data.Bits..&. 0x3f",
  "                        ]",
  "   | otherwise        = [ 0xf0 + (oc `Data.Bits.shiftR` 18)",
  "                        , 0x80 + ((oc `Data.Bits.shiftR` 12) Data.Bits..&. 0x3f)",
  "                        , 0x80 + ((oc `Data.Bits.shiftR` 6) Data.Bits..&. 0x3f)",
  "                        , 0x80 + oc Data.Bits..&. 0x3f",
  "                        ]",
  "}"
  ]
 where
   (stringType,stringTake,stringUncons,stringPack,stringUnpack,stringNilP,stringConsP)
       | byteStrings = ("BS.ByteString", "BS.take", "BS.uncons", "BS.pack", "BS.unpack", "Nothing", "Just (c,s)")
       | otherwise   = ("String",        "take",    "",          "id",      "id",        "[]",      "(c:s)"     )

   ifC cat s = if isUsedCat cf cat then s else ""
   lexComments ([],[])           = []
   lexComments (xs,s1:ys) = '\"' : s1 ++ "\"" ++ " [.]* ; -- Toss single line comments\n" ++ lexComments (xs, ys)
   lexComments (([l1,l2],[r1,r2]):xs,[]) = concat
                                        [
                                        '\"':l1:l2:"\" ([$u # \\", -- FIXME quotes or escape?
                                        r1:"] | \\",
                                        r1:"+ [$u # [\\",
                                        r1:" \\",
                                        r2:"]])* (\"",
                                        r1:"\")+ \"",
                                        r2:"\" ;\n",
                                        lexComments (xs, [])
                                        ]
   lexComments (_ : xs, []) = lexComments (xs,[])
---   lexComments (xs,(_:ys)) = lexComments (xs,ys)

   -- tokens consisting of special symbols
   pTSpec [] = ""
   pTSpec _ = "@rsyms\n    { tok (\\p s -> PT p (eitherResIdent (TV . share) s)) }"

   userDefTokenTypes = unlines
     [printRegAlex exp ++
      "\n    { tok (\\p s -> PT p (eitherResIdent (T_"  ++ show name ++ " . share) s)) }"
      | (name,exp) <- tokenPragmas cf]
   userDefTokenConstrs = unlines
     [" | T_" ++ name ++ " !"++stringType | name <- tokenNames cf]
   userDefTokenPrint = unlines
     ["  PT _ (T_" ++ name ++ " s) -> s" | name <- tokenNames cf]

   ident =
     "$l $i*\n    { tok (\\p s -> PT p (eitherResIdent (TV . share) s)) }"
     --ifC "Ident"  "<ident>   ::= ^l ^i*   { ident  p = PT p . eitherResIdent TV }"


data BTree = N | B String Int BTree BTree

instance Show BTree where
    showsPrec _ N = showString "N"
    showsPrec n (B s k l r) = wrap (showString "b " . shows s  . showChar ' '. shows k  . showChar ' '
                                    . showsPrec 1 l . showChar ' '
                                    . showsPrec 1 r)
        where wrap f = if n > 0 then showChar '(' . f . showChar ')' else f

sorted2tree :: [(String,Int)] -> BTree
sorted2tree [] = N
sorted2tree xs = B x n (sorted2tree t1) (sorted2tree t2) where
  (t1, (x,n) : t2) = splitAt (length xs `div` 2) xs


-------------------------------------------------------------------
-- Inlined version of @BNFC.Backend.Haskell.RegToAlex@.
-- Syntax has changed...
-------------------------------------------------------------------

-- modified from pretty-printer generated by the BNF converter

-- the top-level printing method
printRegAlex :: Reg -> String
printRegAlex = render . prt 0

render :: [String] -> String
render = \case
    "["      : ts -> cons "["  $ render ts
    "("      : ts -> cons "("  $ render ts
    t  : "," : ts -> cons t    $ space "," $ render ts
    t  : ")" : ts -> cons t    $ cons ")"  $ render ts
    t  : "]" : ts -> cons t    $ cons "]"  $ render ts
    t        : ts -> space t   $ render ts
    _             -> ""
  where
  cons s t  = s ++ t
  space t s = if null s then t else t ++ " " ++ s

parenth :: [String] -> [String]
parenth ss = ["("] ++ ss ++ [")"]

-- the printer class does the job
class Print a where
  prt :: Int -> a -> [String]
  prtList :: [a] -> [String]
  prtList = concatMap (prt 0)

instance Print a => Print [a] where
  prt _ = prtList

instance Print Char where
  prt _ = \case
    '\n'             -> ["\\n"]
    '\t'             -> ["\\t"]
    c | isAlphaNum c -> [[c]]
    c | isPrint c    -> ['\\':[c]]
    c                -> ['\\':show (ord c)]

  prtList = map (concat . prt 0)

prPrec :: Int -> Int -> [String] -> [String]
prPrec i j = if j<i then parenth else id

instance Print Ident where
  prt _ (Ident i) = [i]

instance Print Reg where
  prt i e = case e of
   RSeq reg0 reg    -> prPrec i 2 (prt 2 reg0 ++ prt 3 reg)
   RAlt reg0 reg    -> prPrec i 1 (concat [prt 1 reg0 , ["|"] , prt 2 reg])
   RMinus reg0 reg  -> prPrec i 1 (concat [prt 2 reg0 , ["#"] , prt 2 reg])
   RStar reg        -> prPrec i 3 (prt 3 reg ++ ["*"])
   RPlus reg        -> prPrec i 3 (prt 3 reg ++ ["+"])
   ROpt reg         -> prPrec i 3 (prt 3 reg ++ ["?"])
   REps             -> prPrec i 3 ["()"]
   RChar c          -> prPrec i 3 (prt 0 c)
   RAlts str        -> prPrec i 3 (concat [["["],prt 0 str,["]"]])
   RSeqs str        -> prPrec i 2 (concatMap (prt 0) str)
   RDigit           -> prPrec i 3 ["$d"]
   RLetter          -> prPrec i 3 ["$l"]
   RUpper           -> prPrec i 3 ["$c"]
   RLower           -> prPrec i 3 ["$s"]
   RAny             -> prPrec i 3 ["$u"]
