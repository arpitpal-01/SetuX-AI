"use client";

import { createContext, useContext, useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "./supabase";

export type Role = "USER" | "OFFICER" | "ADMIN";
export type Profile = { id: string; full_name: string; email: string; role: Role; department_id: string | null };

type AuthContextValue = {
  session: Session | null;
  profile: Profile | null;
  loading: boolean;
  configured: boolean;
  signOut: () => Promise<void>;
};

const AuthContext = createContext<AuthContextValue>({ session: null, profile: null, loading: true, configured: Boolean(supabase), signOut: async () => undefined });

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const client = supabase;
    if (!client) { setLoading(false); return; }
    let mounted = true;
    const loadProfile = async (nextSession: Session | null) => {
      if (!mounted) return;
      setSession(nextSession);
      if (!nextSession) { setProfile(null); setLoading(false); return; }
      const { data } = await client.from("profiles").select("id, full_name, email, role, department_id").eq("id", nextSession.user.id).single();
      if (mounted) { setProfile(data as Profile | null); setLoading(false); }
    };
    client.auth.getSession().then(({ data }) => loadProfile(data.session));
    const { data: listener } = client.auth.onAuthStateChange((_event, nextSession) => { void loadProfile(nextSession); });
    return () => { mounted = false; listener.subscription.unsubscribe(); };
  }, []);

  const signOut = async () => { if (supabase) await supabase.auth.signOut(); };
  return <AuthContext.Provider value={{ session, profile, loading, configured: Boolean(supabase), signOut }}>{children}</AuthContext.Provider>;
}

export function useAuth() { return useContext(AuthContext); }