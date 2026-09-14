"use client";

import { FormEvent, useEffect, useState } from "react";
import { ArrowRight, CheckCircle2, Eye, EyeOff, ShieldCheck, Sparkles } from "lucide-react";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabase";
import { useAuth } from "../../lib/auth-context";

const demoAccounts = [
  { role: "Citizen", email: "demo.citizen@setux.test" },
  { role: "Officer", email: "demo.officer@setux.test" },
  { role: "Admin", email: "demo.admin@setux.test" },
];
const demoPassword = "SetuXDemo2026!";

export default function AuthPage() {
  const router = useRouter();
  const { session } = useAuth();
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  useEffect(() => { if (session) router.replace("/dashboard/user"); }, [router, session]);

  const fillDemo = (email: string) => {
    const emailInput = document.querySelector<HTMLInputElement>('input[name="email"]');
    const passwordInput = document.querySelector<HTMLInputElement>('input[name="password"]');
    if (!emailInput || !passwordInput) return;
    emailInput.value = email;
    passwordInput.value = demoPassword;
    emailInput.dispatchEvent(new Event("input", { bubbles: true }));
    passwordInput.dispatchEvent(new Event("input", { bubbles: true }));
  };

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); setLoading(true); setError(""); setMessage("");
    if (!supabase) { setError("Supabase is not configured. Add the values from .env.example to .env.local."); setLoading(false); return; }
    const form = new FormData(event.currentTarget);
    const email = String(form.get("email"));
    const password = String(form.get("password"));
    const result = mode === "login"
      ? await supabase.auth.signInWithPassword({ email, password })
      : await supabase.auth.signUp({ email, password, options: { data: { full_name: String(form.get("fullName") || "Citizen") } } });
    if (result.error) {
      const text = result.error.message.toLowerCase();
      setError(text.includes("invalid api key") ? "Supabase rejected the API key. Update .env.local with the current public key." : result.error.message);
    } else if (mode === "signup") setMessage("Account created. Check your email if confirmation is enabled, then sign in.");
    else router.replace("/dashboard/user");
    setLoading(false);
  };

  return <main className="auth-page">
    <section className="auth-brand-panel"><div className="brand auth-brand"><div className="brand-mark"><span>+</span></div><div><strong>SETUX<span>AI</span></strong><small>GOVERNMENT SERVICES</small></div></div><div className="auth-pitch"><p className="eyebrow">FROM APPLICATION TO ACTION</p><h1>Government services, made easier.</h1><p>SetuX helps citizens submit better applications and helps officers make informed, transparent decisions.</p><div className="auth-proof"><div><CheckCircle2 size={16} /><span>Secure document handling</span></div><div><CheckCircle2 size={16} /><span>Human decision, AI preparation</span></div><div><CheckCircle2 size={16} /><span>Real-time application updates</span></div></div></div><small className="auth-legal"><ShieldCheck size={13} /> Your information is protected with secure access controls.</small></section>
    <section className="auth-form-panel"><div className="auth-form-wrap"><div className="mobile-auth-logo"><Sparkles size={18} /> SETUX AI</div><div className="auth-tabs"><button className={mode === "login" ? "selected" : ""} onClick={() => setMode("login")}>Sign in</button><button className={mode === "signup" ? "selected" : ""} onClick={() => setMode("signup")}>Create account</button></div><p className="eyebrow">WELCOME TO SETUX</p><h2>{mode === "login" ? "Sign in to your workspace" : "Create your citizen account"}</h2><p className="auth-muted">{mode === "login" ? "Continue where you left off." : "Public accounts start with citizen access."}</p><form onSubmit={submit}>{mode === "signup" && <label>Full name<input name="fullName" required placeholder="Your full name" /></label>}<label>Email address<input name="email" type="email" required placeholder="you@example.com" /></label><label>Password<div className="password-input"><input name="password" type={showPassword ? "text" : "password"} required minLength={6} placeholder="At least 6 characters" /><button type="button" onClick={() => setShowPassword(!showPassword)}>{showPassword ? <EyeOff size={16} /> : <Eye size={16} />}</button></div></label>{mode === "login" && <button type="button" className="forgot-btn" onClick={() => setMessage("Password reset can be enabled from Supabase Auth settings.")}>Forgot password?</button>}{error && <p className="auth-error">{error}</p>}{message && <p className="auth-success">{message}</p>}<button className="auth-submit" disabled={loading}>{loading ? "Please wait..." : mode === "login" ? "Sign in" : "Create account"}<ArrowRight size={16} /></button></form>
      {mode === "login" && <div className="demo-access"><div className="demo-access-heading"><Sparkles size={13} /><span>Demo access</span><small>Password: {demoPassword}</small></div><div className="demo-role-buttons">{demoAccounts.map((account) => <button type="button" key={account.role} onClick={() => fillDemo(account.email)}><strong>{account.role}</strong><small>{account.email}</small></button>)}</div></div>}
      <p className="auth-switch">{mode === "login" ? "New to SetuX?" : "Already have an account?"} <button onClick={() => setMode(mode === "login" ? "signup" : "login")}>{mode === "login" ? "Create account" : "Sign in"}</button></p></div></section>
  </main>;
}
