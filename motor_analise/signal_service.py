from __future__ import annotations


class TechnicalSignalService:
    """Interpreta cálculos; não envia ordens e não representa probabilidade de ganho."""

    def evaluate(self, price: float, values: dict) -> dict:
        score = 0
        reasons: list[str] = []
        ema9, ema21, ema80 = values.get("ema9"), values.get("ema21"), values.get("ema80")
        if all(v is not None for v in (ema9, ema21, ema80)):
            if price > ema21 and ema9 > ema21 > ema80:
                score += 30; reasons.append("Preço e médias alinhados para alta")
            elif price < ema21 and ema9 < ema21 < ema80:
                score -= 30; reasons.append("Preço e médias alinhados para baixa")
        macd_hist = values.get("macd_hist")
        if macd_hist is not None: score += 15 if macd_hist > 0 else -15
        rsi = values.get("rsi")
        if rsi is not None:
            score += 10 if 52 <= rsi <= 70 else -10 if 30 <= rsi <= 48 else 0
            if rsi > 70: reasons.append("RSI em sobrecompra")
            if rsi < 30: reasons.append("RSI em sobrevenda")
        vwap = values.get("vwap")
        if vwap: score += 15 if price > vwap else -15
        volume, average = values.get("volume"), values.get("volume_average20")
        if volume is not None and average:
            score += (10 if score >= 0 else -10) if volume > average * 1.2 else 0
        adx = values.get("adx")
        if adx is not None and adx >= 25: score += 10 if score >= 0 else -10
        score = max(-100, min(100, score))
        label = "forte pressão compradora" if score >= 61 else "pressão compradora" if score >= 21 else "forte pressão vendedora" if score <= -61 else "pressão vendedora" if score <= -21 else "cenário neutro ou lateral"
        trend = "Tendência de alta" if score >= 21 else "Tendência de baixa" if score <= -21 else "Mercado lateral"
        return {"score": score, "label": label, "trend": trend, "reasons": reasons}

    def combined(self, assets: list[dict]) -> dict:
        scores = [item.get("signal", {}).get("score") for item in assets]
        valid = [value for value in scores if isinstance(value, (int, float))]
        if not valid: return {"score": None, "label": "Dados insuficientes"}
        score = round(sum(valid) / len(valid))
        label = "Contexto favorável" if score >= 21 else "Contexto desfavorável" if score <= -21 else "Contexto neutro"
        return {"score": score, "label": label, "note": "Leitura contextual de ES e EWZ; não é probabilidade nem recomendação."}
