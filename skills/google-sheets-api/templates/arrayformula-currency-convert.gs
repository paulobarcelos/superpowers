=ARRAYFORMULA(IF(B2:B="",,
  MAP(
    B2:B,
    LAMBDA(sel,
      IF(sel="",,
        LET(
          rowMatch, MATCH(sel, Foo!A:A, 0),
          amount, INDEX(Foo!B:B, rowMatch),
          currency, INDEX(Foo!C:C, rowMatch),
          amount * IF(currency="USD", 1, GOOGLEFINANCE("CURRENCY:" & currency & "USD"))
        )
      )
    )
  )
))
